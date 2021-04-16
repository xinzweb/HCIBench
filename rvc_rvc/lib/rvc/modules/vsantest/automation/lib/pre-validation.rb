#!/usr/bin/ruby
require 'fileutils'
require 'ipaddr'
require 'resolv'
require 'shellwords'
require 'yaml'
require_relative "util.rb"
require_relative "rvc-util.rb"
require_relative 'validate_subnets.rb'

@log_file = "#{$log_path}/prevalidation/pre-validation.log"
@ip_Address = _get_ip_addr
@http_place = "https://#{@ip_Address}:8443/output/hcibench_logs/prevalidation/"
@warning_msg = ""
@dc_path, @dc_path_escape = "",""
@cl_path, @cl_path_escape = "",""
@has_vsan = false
@ds_ids = []
@policy_rule_map = {}
@default_policy_rule_map = {}
@vsan_datastores = {}
@ds_urls = {}
@rp_find = false
@fd_find = false
@hosts_list = []
@temp_folder = "/tmp/" + $tool + "_temp/"
@network_ref = ""
@vsan_ds_rep_factor = {}

def prepareLogs
  `mkdir -p /opt/automation/logs/prevalidation`
  `rm -rf #{$basedir}/../logs/prevalidation/*`
  `cp #{$basedir}/../conf/perf-conf.yaml #{$basedir}/../logs/prevalidation/hcibench.cfg`
  `sed -i '/username/d' #{$basedir}/../logs/prevalidation/hcibench.cfg`
  `sed -i '/password/d' #{$basedir}/../logs/prevalidation/hcibench.cfg`
  `cat /etc/hcibench_version > #{@log_file}`
end

def puts(o)
  o = "#{Time.now}: " + o
  open(@log_file, 'a') do |f|
    f << o + "\n"
  end
  super(o)
end

def err_msg(msg)
  puts "------------------------------------------------------------------------------"
  puts "#{msg}"
  puts "------------------------------------------------------------------------------"
  exit(255)
end

def warning_msg(msg)
  @warning_msg += msg + "\n------------------------------------------------------------------------------\n"
end

def validate_if_variable_empty var
  if (var.to_s == "" or !var) and (!!var != var)
    err_msg "A REQUIRED Parameter is NULL, please re-check your configuration file!"
  end
end

def validate_subnets
  begin
    msg = ValidateSubnets.new.ipv4_conflict?('docker0')
    err_msg "There are interfaces that conflict with the internal docker network:\n#{msg.join("\n")}" if msg
    if $static_enabled
      msg = ValidateSubnets.new.ipv4_subnet_conflict?('docker0', $starting_static_ip, $static_ip_size)
      err_msg "The selected static network conflicts with the internal docker network:\n#{msg.join("\n")}" if msg
    end
  rescue => e
    err_msg "There was an error while validating the subnets: #{e.message}"
  end
end

def validate_vc_info
  # Validating VC hostname and credentials
  puts "Validating VC IP and Credential..."
  # if vc is not ipv4
  if !($vc_ip =~ Resolv::IPv4::Regex)
    cmd_run = system("ping -c 5 #{$vc_ip} >> #{@log_file} 2>&1")
    err_msg "HCIBench Can't Resolve the vCenter Hostname or Can't communicate with the vCenter, Please Check the DNS or the Network Configuration and Try Again" if !cmd_run
    result = `timeout 5 bash -c 'cat < /dev/null > /dev/tcp/#{IPSocket.getaddress($vc_ip)}/443'`
    err_msg "Cannot Connect to vCenter #{$vc_ip} Port 443, please check your Network Firewall setting!" if $?.exitstatus != 0
    err_msg "Cannot Resolve vCenter #{$vc_ip} Hostname, Please Check the DNS Settings!" if _get_ip_from_hostname($vc_ip) == "Unresolvable"
  end
  err_msg "HCIBench Can NOT Take \":\" in the vCenter Username." if $vc_username.include? ":"
  
  arg = " -c 'exit' -q >> #{@log_file} 2>&1"
  cmd_run = system("rvc " + $vc_rvc + arg)
  if !cmd_run
    err_msg "VC #{$vc_ip} IP or Credential Info incorrect!"
  else
    puts "VC IP and Credential Validated"
  end
end

def validate_dc_info
  # Validating Datacenter existence
  puts "Validating Datacenter #{$dc_name}..."
  err_msg "You have duplicated Datacenter name #{$dc_name}, please use unique name" if _is_duplicated "dc", $dc_name, ""
  @dc_path, @dc_path_escape = _get_dc_path
  if @dc_path == ""
    err_msg "Datacenter #{$dc_name} doesn't exist!"
  else
    puts "Datacenter #{$dc_name} Validated"
  end
end

def validate_cluster_info
  # Validating Cluster
  puts "Validating Cluster #{$cluster_name}..."
  err_msg "You have duplicated Cluster name #{$cluster_name}, please use unique name" if _is_duplicated "cl", $cluster_name, '/'+ @dc_path.gsub(/^\/$vc_ip/,'')
  
  @cl_path, @cl_path_escape = _get_cl_path
  if @cl_path == ""
    err_msg "Cluster #{$cluster_name} doesn't exist!"
  else
    puts "Cluster #{$cluster_name} Validated"
  end

  @drs_mode = `rvc #{$vc_rvc} --path #{@cl_path_escape} -c 'info .' -c 'exit' -q | grep -E "^DRS:" | cut -d " " -f2`.chomp
  puts "Cluster #{$cluster_name} has DRS mode: #{@drs_mode}"
  warning_msg "Cluster #{$cluster_name} has DRS mode: #{@drs_mode}, which may cause VMs distribution imbalance, recommend to disable DRS before running HCIBench testing." if @drs_mode == "fullyAutomated"

  puts "Validating If Any Hosts in Cluster #{$cluster_name} is in Maintainance Mode..."
  hosts_in_maintainance = `rvc #{$vc_rvc} --path #{@cl_path_escape} -c 'vsantest.perf.find_hosts_in_maintainance .' -c 'exit' -q | awk -F/ '{print $NF}'`.split("\n")
  if hosts_in_maintainance != []
    hosts_in_maintainance.each do |host|
      err_msg "Host #{host} is in maintainance mode, please exit maintainance mode and try again!"
    end
  else
    puts "All the Hosts in Cluster #{$cluster_name} are not in Maitainance Mode"
  end

  # Hosts hostname resolvable and accessible
  @hosts_list = _get_deploy_hosts_list
  @hosts_list.each do |host|
    err_msg "Cannot Resolve Host #{host} Hostname, Please Check the DNS Settings!" if !_is_ip(host) and _get_ip_from_hostname(host) == "Unresolvable"
  end
end

def validate_rp_info
  # Validating Resource Pool
  @rps_path_escape = Shellwords.escape("/#{$vc_ip}/#{@dc_path}/#{@cl_path}/resourcePool/pools")
  if $resource_pool_name != ""
    rp_arr = `rvc #{$vc_rvc} --path #{@rps_path_escape} -c 'find .' -c 'exit' -q | tee -a #{@log_file}`.encode('UTF-8', :invalid => :replace).split("\n")
    rp_arr.each do |rp|
      @rp_find = true if rp[/#{Regexp.escape $resource_pool_name}$/] and rp.partition(' ').last == $resource_pool_name
    end
    if @rp_find
      puts "Resource Pool #{$resource_pool_name} Validated"
    else
      err_msg "Resource Pool #{$resource_pool_name} doesn't exist!"
    end
  end
end

def validate_vm_folder_info
  # Validating VM Folder
  @fd_path_escape = Shellwords.escape("/#{$vc_ip}/#{@dc_path}/vms")
  if $fd_name != ""
    fd_arr = `rvc #{$vc_rvc} --path #{@fd_path_escape} -c 'ls .' -c 'exit' -q | tee -a #{@log_file} `.encode('UTF-8', :invalid => :replace).split("\n")
    fd_arr.each do |fd|
      fd = fd.gsub("\e[0m","").gsub("/","")
      if fd[/#{Regexp.escape $fd_name}$/] and fd.partition(' ').last == $fd_name
        @fd_path_escape = Shellwords.escape("/#{$vc_ip}/#{@dc_path}/vms/#{$fd_name}")
        type = `rvc #{$vc_rvc} --path #{@fd_path_escape} -c 'what .' -c 'exit' -q`.encode('UTF-8', :invalid => :replace).split(" ")[-1]
        if type == "Folder"
          @fd_find = true
          break
        end
      end
    end
    if @fd_find
      puts "VM Folder #{$fd_name} Validated"
    else
      err_msg "VM Folder #{$fd_name} doesn't exist!"
    end
  end
end

def validate_network_info
  network_name_cmd = $network_name.gsub('"','\"')
  puts "Validating Network #{$network_name}..."
  has_duplicate_network_name = Shellwords.escape(%{vsantest.perf.has_duplicate_network_name . "#{network_name_cmd}"})
  `echo "Network name has duplication?" | tee -a #{@log_file}`
  has_duplicate = `rvc #{$vc_rvc} --path #{@cl_path_escape} -c #{has_duplicate_network_name} \
  -c 'exit' -q | tee -a #{@log_file}`.chomp
  err_msg "Network #{$network_name} has duplication, the Network name must be unique!" if has_duplicate == 'true'

  get_network_by_name_escape = Shellwords.escape(%{vsantest.perf.get_network_by_name . "#{network_name_cmd}"})
  get_network_ref_by_name_escape = Shellwords.escape(%{vsantest.perf.get_network_ref_by_name . "#{network_name_cmd}"})
  nw_path = `rvc #{$vc_rvc} --path #{@dc_path_escape} -c #{get_network_by_name_escape} -c 'exit' -q \
  | tee -a #{@log_file}`.encode('UTF-8', :invalid => :replace).chomp
  if nw_path=="NOT FOUND!"
    err_msg "Network #{$network_name} doesn't exist!"
  else
    @network_ref = `rvc #{$vc_rvc} --path #{@dc_path_escape} -c #{get_network_ref_by_name_escape} -c 'exit' -q \
  | tee -a #{@log_file}`.encode('UTF-8', :invalid => :replace).chomp
    puts "Network #{$network_name} Validated"
  end

  puts "Checking If Network #{$network_name} is accessible from all the hosts of #{$cluster_name}..."
  @hosts_list.each do |host|
    network_path_escape = Shellwords.escape("/#{$vc_ip}/#{@dc_path}/#{@cl_path}/hosts/#{host}/networks")
    run_cmd = ""
    nw_arr = `rvc #{$vc_rvc} --path #{network_path_escape} -c 'find .' -c 'exit' -q \
    | tee -a #{@log_file}`.encode('UTF-8', :invalid => :replace).split("\n")
    nw_arr.each do |nw|
      run_cmd = nw.partition(' ').last if nw[/#{Regexp.escape $network_name}$/] and nw.partition(' ').last == $network_name
    end
    if run_cmd == ""
      err_msg "Network #{$network_name} is not accessible from host #{host}"
    else
      puts "Network #{$network_name} is accessible from host #{host} "
    end
  end
  puts "Network #{$network_name} is accessible from all the hosts of #{$cluster_name}"

  puts "Validating Type of Network #{$network_name}..."
  get_network_type_by_name_escape = Shellwords.escape(%{vsantest.perf.get_network_type_by_name . "#{network_name_cmd}"})
  network_type = `rvc #{$vc_rvc} --path #{@dc_path_escape} -c #{get_network_type_by_name_escape} -c 'exit' -q \
  | tee -a #{@log_file} `.encode('UTF-8', :invalid => :replace).chomp
  puts "Network #{$network_name} Type is #{network_type}"
end

def validate_datastore_info
  if $datastore_names
    $datastore_names.each do |datastore_name|
      @ds_path, @ds_path_escape = [],"",""
      @ds_path, @ds_path_escape = _get_ds_path_escape(datastore_name)
      if @ds_path == ""
        err_msg "Datastore #{datastore_name} doesn't exist!"
      else
        puts "Datastore #{datastore_name} Validated"
      end

      puts "Checking Datastore #{datastore_name} type..."
      ds_type = `rvc #{$vc_rvc} --path #{@ds_path_escape} -c "info ." -c 'exit' -q | grep 'type:' | awk '{print $2}'`.encode('UTF-8', :invalid => :replace).chomp
      @has_vsan = true if ds_type == 'vsan'
      puts "Datastore #{datastore_name} type is #{ds_type}"

      puts "Getting Datastore #{datastore_name} id..."
      ds_id = `rvc #{$vc_rvc} --path #{@ds_path_escape} -c 'vsantest.perf.get_datastore_id .' -c 'exit' -q \
      | tee -a #{@log_file}`.encode('UTF-8', :invalid => :replace).chomp
      @ds_ids << ds_id
      @ds_urls[`rvc #{$vc_rvc} --path #{@ds_path_escape} -c "show ." -c 'exit' -q | grep "url:" | awk '{print $2}' | tee -a #{@log_file}`.chomp] = datastore_name

      puts "Checking If Datastore #{datastore_name} is accessible from any of the hosts of #{$cluster_name}..."
      ds_host_list = `rvc #{$vc_rvc} --path #{@ds_path_escape} -c 'find hosts' -c 'exit' -q | tee -a #{@log_file} `.encode('UTF-8', :invalid => :replace).split("\n") 
      found = false
      for host_in_ds in ds_host_list
        host = host_in_ds.partition('/').last
        if @hosts_list.include? host
          puts "Datastore #{datastore_name} is accessible from host #{host}"
          found = true
        end
      end
      err_msg "Datastore #{datastore_name} is not accessible from any of hosts in cluster #{$cluster_name}" if not found
    end
  end
end

def validate_vsan_info
  @vsan_datastores = _get_vsandatastore_in_cluster
  vsan_datastore_names = @vsan_datastores.keys & $datastore_names
  if vsan_datastore_names != []
    puts "vSAN is Enabled in Cluster #{$cluster_name}, the vSAN Datastore for test is #{vsan_datastore_names.join(', ')}"
  else
    err_msg "Can't find any vSAN Datastores for test"
  end

  vsan_datastore_names.each do |vsan_datastore_name|
    default_policy_rule_map = {}
    vsan_default_policy_name, rules = _get_vsan_default_policy(vsan_datastore_name)
    rules.each do |rule|
      rule = rule.delete(' ')
      default_policy_rule_map[rule.split(":").first] = rule.split(":").last if not rule.include? "Rule-Set"
    end
    policy_pftt = default_policy_rule_map["VSAN.hostFailuresToTolerate"] || "1"
    policy_sftt = default_policy_rule_map["VSAN.subFailuresToTolerate"] || "0"
    policy_ftm = default_policy_rule_map["VSAN.replicaPreference"] || "RAID-1 (Mirroring) - Performance"
    if policy_ftm.include? "RAID-1"
      rep_factor = policy_pftt.to_i + 1 
    else
      rep_factor = 1.33 if policy_pftt.to_i == 1
      rep_factor = 1.66 if policy_pftt.to_i == 2
    end
    @vsan_ds_rep_factor[vsan_datastore_name] = rep_factor * ( policy_sftt.to_i + 1 )
    vsan_capacity = @vsan_datastores[vsan_datastore_name]["capacity"]
    vsan_freespace = @vsan_datastores[vsan_datastore_name]["freeSpace"]
    local = "Local"
    remote_cluster_name = ""
    if not @vsan_datastores[vsan_datastore_name]["local"]
      local = "Remote"
      remote_cluster_name = _get_vsan_cluster_from_datastore(vsan_datastore_name)
      ps_enabled = _is_ps_enabled(remote_cluster_name)
      warning_msg "Please turn on vSAN Performance Service for remote vSAN cluster #{remote_cluster_name} in order to monitor vSAN while testing is running" if (not ps_enabled) and (not $vsan_debug)
      err_msg "Please turn on vSAN Performance Service for cluster #{remote_cluster_name} as it's needed for vSAN debug mode" if (not ps_enabled) and $vsan_debug
    else
      ps_enabled = _is_ps_enabled
      err_msg "Please turn on vSAN Performance Service for cluster #{$cluster_name} as it's needed for vSAN debug mode" if (not ps_enabled) and $vsan_debug
      warning_msg "Please turn on vSAN Performance Service for cluster #{$cluster_name} in order to monitor vSAN while testing is running" if (not ps_enabled) and (not $vsan_debug)
    end
    puts "vSAN #{local} Datastore name is #{vsan_datastore_name}, capacity is #{vsan_capacity} GB and freespace is #{vsan_freespace} GB, the default policy is #{vsan_default_policy_name}"
  
    if $storage_policy and not $storage_policy.empty? and not $storage_policy.strip.empty?
      puts "Validating storage policy #{$storage_policy}..."
      compliant_ids = _get_compliant_datastore_ids_escape($storage_policy)
      err_msg "Unable to find the storage policy #{$storage_policy} or Unable to find compliant datastores of policy #{$storage_policy}" if compliant_ids == []
      err_msg "The storage policy #{$storage_policy} is not compatible with any of the datastores specified." if (@ds_ids & compliant_ids) == []
      rules = _get_storage_policy_rules($storage_policy)
      rules.each do |rule|
        rule = rule.delete(' ')
        @policy_rule_map[rule.split(":").first] = rule.split(":").last if not rule.include? "Rule-Set"
      end
      policy_pftt = @policy_rule_map["VSAN.hostFailuresToTolerate"] || "1"
      policy_sftt = @policy_rule_map["VSAN.subFailuresToTolerate"] || "0"
      policy_ftm = @policy_rule_map["VSAN.replicaPreference"] || "RAID-1 (Mirroring) - Performance"
      if policy_ftm.include? "RAID-1"
        rep_factor = policy_pftt.to_i + 1 
      else
        rep_factor = 1.33 if policy_pftt.to_i == 1
        rep_factor = 1.66 if policy_pftt.to_i == 2
      end
      @vsan_ds_rep_factor[vsan_datastore_name] = rep_factor * ( policy_sftt.to_i + 1 )
    end
  end
end

def validate_misc_info
  if $clear_cache or $vsan_debug
    err_msg "At least one vSAN Datastore should be Included if Clear Cache or vSAN Debug is enabled!" if !@has_vsan
    hosts_list_drop_cache = []
    (@vsan_datastores.keys & $datastore_names).each do |datastore_name|
      hosts_list_drop_cache = hosts_list_drop_cache | _get_hosts_list(_get_vsan_cluster_from_datastore(datastore_name))
    end
    hosts_list_drop_cache = hosts_list_drop_cache | _get_hosts_list if $vsan_debug

    hosts_list_drop_cache.each do |host|
      err_msg "Cannot Resolve Host #{host} Hostname, Please Check the DNS Settings!" if !_is_ip(host) and _get_ip_from_hostname(host) == "Unresolvable"
      err_msg "Check your network see if port 22 is blocked from HCIBench to Host #{host}, otherwise the Host #{host} Username or Password is NOT correct or SSH Service is not Enabled!" if !ssh_valid(host,$host_username,$host_password)
    end
    puts "Hosts credential and SSH service is verified."
  end
  err_msg "vSAN Datastore should be Included if Easy Run is applied!" if $easy_run and !@has_vsan
  
  #Validate staic info
  #Start static if the box is checked
  if $static_enabled
    puts "Validating IP pool availability..."
    system("ifconfig -s eth1 0.0.0.0")
    find_ip = false
    ip_required = [_get_num_of_tvm_to_deploy,_get_num_of_vm_to_deploy].max
    if _range_big_enough
      ip_pool = _get_ip_pools.uniq
      if ip_pool.size >= ip_required
        eth1_ip = $eth1_ip
        find_ip = true
      else
        err_msg "We need at least #{$tvm_num} IPs available in order to testing cluster inter-connectivity, and now these IPs are available: #{ip_pool}" if ip_pool.size < $tvm_num
        ip_needed = ip_required - ip_pool.size
        existing_vm_network_map = eval(`rvc #{$vc_rvc} --path #{@cl_path_escape} -c "vsantest.perf.get_vm_network 'hosts/*/vms/#{$vm_prefix}-*'" -c 'exit' -q | tee -a #{@log_file}`.encode('UTF-8', :invalid => :replace))
        if not existing_vm_network_map.empty?
          ip_recycle = []
          existing_vm_network_map.keys.each do |vm_name|
            if existing_vm_network_map[vm_name].has_key?(@network_ref) and $occupied_ips.include?(existing_vm_network_map[vm_name][@network_ref])
              ip_recycle << existing_vm_network_map[vm_name][@network_ref]
              ip_needed -= 1
            end
          end
        end
        if ip_needed > 0
          err_msg "Not enough IP Addresses available, these #{ip_pool.size} IP are currently available: #{ip_pool} \n
          these #{$occupied_ips.uniq.size} IPs are currently occupied: #{$occupied_ips.uniq} \n
          these #{ip_recycle.uniq.size} occupied IPs will be reused upon guest VMs deployment: #{ip_recycle.uniq} \n
          but we still need #{ip_needed} IP released to get #{ip_required} IP ready for testing"
        else
          warning_msg "There aren't enough available IP address(#{ip_required} needed) available for deploying guest VMs. However, there are #{ip_recycle.uniq} IPs will be reused either by deleting or reusing the existing guest VMs so you can still go ahead to start testing."
          eth1_ip = $eth1_ip
          find_ip = true 
        end      
      end
    else
      err_msg "The IP range defined is not big enough for all guest VMs"
    end
    system("ifconfig -s eth1 #{eth1_ip}/#{$static_ip_size}") if find_ip
  end
end

def validate_cluster_connection
  puts "Validating cluster inter-connectivity..."
  tvm_arr = `rvc #{$vc_rvc} --path #{@cl_path_escape} -c "what 'hosts/*/vms/hci-tvm-*'" -c 'exit' -q \
  | tee -a #{@log_file}`.split("\n")
  if tvm_arr.size != 1 or `rvc #{$vc_rvc} --path #{@cl_path_escape} -c "find 'hosts/*/vms/hci-tvm-*'" -c 'exit' -q \
    | tee -a #{@log_file}`.split("\n").size != 0
    err_msg "You Have #{tvm_arr.size} VM with the Prefix as hci-tvm, Please Rename or Delete Those VMs."
  end

  # load $clean_tvm_file
  `ruby #{$cleanuptvmfile}`
  result = `ruby #{$deploytvmfile} >> #{@log_file} 2>&1`
  return_value = $?.exitstatus
  if return_value != 0
    system("ifconfig -s eth1 0.0.0.0; ifconfig eth1 down; ifconfig eth1 up") if $static_enabled
    `ruby #{$cleanuptvmfile}`
    if return_value == 255
      err_msg "Unable to deploy test VM, please check the logs in /opt/automation/logs/prevalidation or <a href=\"#{@http_place}\" target='_blank'>here</a> to identify which host was failed to deploy VM"
    elsif return_value == 254
      err_msg "Cluster inter-connectivity validation failed, please check the hcitvm logs in /opt/automation/logs/prevalidation or <a href=\"#{@http_place}\" target='_blank'>here</a> to identify the issue"
    elsif return_value == 253
      err_msg "Unable to SSH to hcitvm, please check if your network allow SSH to go through"
    else #elsif return_value == 250
      err_msg "Unknow Error, please check the hcitvm logs in /opt/automation/logs/prevalidation or <a href=\"#{@http_place}\" target='_blank'>here</a> to identify the issue"
    end
  else
    load $gettvmipfile
    entry = YAML.load_file($tvmlistfile)
    tvms = entry["vms"]
    tvms.each do |tvm|
      cmd = "gip=`netstat -ntp 2>/dev/null| grep ':22' | awk '{print $5}' | cut -d ':' -f1`;"
      cmd += 'timeout -t 5 sh -c "nc -vz $gip 2003" >/dev/null 2>&1;'
      cmd += "echo $?"
      return_code = ssh_cmd(tvm, 'root', 'VMware1!', cmd)
      if return_code.to_i != 0
        warning_msg "Network traffic to HCIBench:2003 is blocked, you can still run the testing, but Grafana live monitoring will not work"
        break
      end
    end
    `ruby #{$cleanuptvmfile}`
    system("ifconfig -s eth1 0.0.0.0; ifconfig eth1 down; ifconfig eth1 up") if $static_enabled
    puts "Cluster inter-connectivity validated"
  end
end

def validate_host_info
  err_msg "Hosts Info Can NOT be empty!" if not $all_hosts
  hosts_list_in_ip = _get_hosts_list_in_ip
  $all_hosts.each do |host|
    puts "Validating Host #{host} IP Address..."
    cmd_run = system("ping -c 5 #{host} > /dev/null 2>&1")
    if !cmd_run
      err_msg "Host #{host} inaccessible!"
    else
      puts "Host #{host} Address Validated"
    end
    puts "Validating If Host #{host} Is In Cluster #{$cluster_name}..."
    Resolv.each_address("#{host}") do |ip|
      if not hosts_list_in_ip.include? ip
        err_msg "Host #{host} Is NOT In Cluster #{$cluster_name}!"
      else
        puts "Host #{host} Is In Cluster #{$cluster_name}"
      end
    end
  end
end

def validate_vm_conf
  
  err_msg "VM Prefix can Only Contain Letters,Digits and -, No More than 7 Characters" if $vm_prefix.size > 7 or $vm_prefix =~ /[^a-z0-9-]/i
  vm_arr = `rvc #{$vc_rvc} --path #{@cl_path_escape} -c "what 'hosts/*/vms/#{$vm_prefix}-*'" -c 'exit' -q \
  | tee -a #{@log_file}`.encode('UTF-8', :invalid => :replace).split("\n")
  
  warning_msg "You have #{vm_arr.size} VM Have the Same Prefix as #{$vm_prefix}, Please Make Sure the VMs are Deployed by HCIBench or OK to be Deleted Otherwise Please Change the VM Name Prefix." if vm_arr.size != 1 or `rvc #{$vc_rvc} --path #{@cl_path_escape} -c "find 'hosts/*/vms/#{$vm_prefix}-*'" -c 'exit' -q | tee -a #{@log_file}`.encode('UTF-8', :invalid => :replace).split("\n").size != 0
  err_msg "Number of VMs #{$vm_num} is not Integer or not greater than 0" if !$vm_num.is_a?(Integer) || $vm_num <= 0
  err_msg "Number of Data Disks #{$number_data_disk} is not Integer or not greater than 0" if !$number_data_disk.is_a?(Integer) || $number_data_disk <= 0
  err_msg "Size of Data Disks #{$size_data_disk} is not Integer or not greater than 0" if !$size_data_disk.is_a?(Integer) || $size_data_disk <= 0
  vm_size = 16 + $size_data_disk * $number_data_disk
  $datastore_names.each do |datastore_name|
    capacity = 0
    freespace = 0
    if _is_vsan(datastore_name)
      rep_factor = @vsan_ds_rep_factor[datastore_name]
      capacity = @vsan_datastores[datastore_name]["capacity"]
      freespace = @vsan_datastores[datastore_name]["freeSpace"]
    else
      rep_factor = 1
      capacity, freespace = _get_datastore_capacity_and_free_space(datastore_name)
    end
    vm_usage = vm_size * rep_factor * $vms_perstore
    ds_usage = capacity.to_i - freespace.to_i
    total_usage = ds_usage + vm_usage

    if 0.8 < (total_usage.to_f)/(capacity.to_f) and (total_usage.to_f)/(capacity.to_f) < 0.9
      warning_msg "Warning, the usage of Datastore #{datastore_name} will be #{total_usage}GB, which exceeds 80% of the Datastore Capacity: #{capacity}GB, Please Consider to decrease the size or number of data disk or the number of VMs.\n(You can ignore this warning message if you already have guest VMs deployed and going to reuse them)"
    end

    if (total_usage.to_f)/(capacity.to_f) > 0.9
      warning_msg "Warning, the usage of Datastore #{datastore_name} will be #{total_usage} GB, which exceeds 90% of the Datastore Capacity: #{capacity}GB, Please decrease the size or number of data disk or the number of VMs.\n(You can ignore this warning message if you already have guest VMs deployed and going to reuse them)"
    end
  end

  ds_hosts_hash = {}
  host_vmnum_hash = {}
  $datastore_names.each do |datastore_name|
    ds_hosts_hash[datastore_name] = _get_hosts_list_by_ds_name(datastore_name) & @hosts_list
  end
  ds_hosts_hash.keys.each do |ds|
    vms_per_store_per_host = ($vms_perstore.to_f/ds_hosts_hash[ds].size.to_f).ceil
    ds_hosts_hash[ds].each do |host|
      if host_vmnum_hash.key?(host)
        host_vmnum_hash[host] += vms_per_store_per_host
      else
        host_vmnum_hash[host] = vms_per_store_per_host
      end
    end
  end
  host_vmnum_hash.keys.each do |host|
    spare_cpu = _get_host_spare_compute_resource(host)[0]
    spare_ram = _get_host_spare_compute_resource(host)[1]
    cpu_to_use = host_vmnum_hash[host] * $num_cpu
    ram_to_use = host_vmnum_hash[host] * $size_ram
    cpu_used_by_guest_vm = _get_resource_used_by_guest_vms(host)[0]
    ram_used_by_guest_vm = _get_resource_used_by_guest_vms(host)[1]
    warning_msg "#{host_vmnum_hash[host]} VMs will be deployed onto host #{host}, each VM has #{$num_cpu} vCPU configured, in this case, the CPU resource of #{host} would be oversubscribed.\nYou can reduce number of vCPU per guest VM or reduce number of VMs to deploy to ease this situation." if spare_cpu.to_i + cpu_used_by_guest_vm.to_i - cpu_to_use <= 0 
    warning_msg "#{host_vmnum_hash[host]} VMs will be deployed onto host #{host}, each VM has #{$size_ram}GB RAM configured, in this case, the Memory of #{host} would be oversubscribed.\nYou can reduce the size of ram per guest VM or reduce number of VMs to deploy to ease this situation." if spare_ram.to_i + ram_used_by_guest_vm.to_i - ram_to_use <= 0 
  end
end

def validate_testing_config
  err_msg "The User Defined Parameter Files Directory #{$self_defined_param_file_path} is NOT Valid!" if !File.directory?($self_defined_param_file_path)
  empty = true
  Dir.foreach($self_defined_param_file_path) do |item|
    next if item == '.' or item == '..'
    empty = false
  end
  err_msg "No Workload Param File Found in the User Defined Workload Param Files Directory #{$self_defined_param_file_path}!" if empty
  err_msg "The Value of warm_up_disk_before_testing: #{$warm_up_disk_before_testing} is Not Valid, which should be NONE, ZERO or RANDOM" if ($warm_up_disk_before_testing != "NONE" and $warm_up_disk_before_testing != "ZERO" and $warm_up_disk_before_testing != "RANDOM")
  err_msg "The Value of testing_duration #{$testing_duration} is Not Valid!" if $testing_duration and (!$testing_duration.is_a?(Integer) or ($testing_duration <= 0))
end

def validate_fio_param
  empty = true
  Dir.foreach($fio_source_path) do |item|
    next if item == '.' or item == '..'
    empty = false
  end
  if empty
    err_msg "No Fio Binary Found, Please place fio binary to /opt/output/fio-source"
  else
    if  `ls #{$fio_source_path} | wc -l`.encode('UTF-8', :invalid => :replace).to_i != 1
      err_msg "Please make sure Fio binary file is the only file in #{$fio_source_path}"
    end
    cmd_run = system("mkdir -p #{@temp_folder} && cp #{$fio_source_path}/* #{@temp_folder} && cd #{@temp_folder} && ./fio --help > /dev/null 2>&1")
    if !cmd_run
      `rm -rf #{@temp_folder}`
      err_msg "The Fio Binary File is NOT Valid, Please Replace the fio binary file in #{$fio_source_path} and Make sure it's the only file in this directory!"
    end
    if !$easy_run
      Dir.foreach($self_defined_param_file_path) do |item|
        next if item == '.' or item == '..'
        cmd_run = system("cd #{@temp_folder} && ./fio -f #{$self_defined_param_file_path}/#{item} --showcmd \
          > #{@temp_folder}out.log 2> #{@temp_folder}err.log")
        if !cmd_run
          err = `cat #{@temp_folder}err.log`.chomp
          `rm -rf #{@temp_folder}`
          err_msg "The fio workload profile #{item} is not defined correctly: " + err
        end
        has_sda = system("grep 'filename=/dev/sda' #{@temp_folder}out.log > /dev/null 2>&1")
        vmdk_num = `grep -o "filename=/dev/sd[0-9a-zA-Z] " #{@temp_folder}out.log | wc -l`.to_i
        if $number_data_disk < vmdk_num
          `rm -rf #{@temp_folder}`
          err_msg "All pre-validate passed, and good to deploy Greenplum cluster!"
        end
        if $number_data_disk == vmdk_num and !has_sda
          `rm -rf #{@temp_folder}`
          err_msg "The disks defined in #{item} should have sda configured because OS disk is the last one"
        end
      end
    end
    `rm -rf #{@temp_folder}`
  end
end

def validate_vdbench_binary
  empty = true
  Dir.foreach($vdbench_source_path) do |item|
    next if item == '.' or item == '..'
    empty = false
  end
  if empty
    err_msg "No VDBENCH Zip File Found in the VDBENCH Source Directory, please upload VDBENCH Zip file!"
  else
    err_msg "Please make sure Vdbench zip file is the only file in #{$vdbench_source_path}" if  `ls #{$vdbench_source_path} | wc -l`.encode('UTF-8', :invalid => :replace).to_i != 1
    cmd_run = system("mkdir -p #{@temp_folder} && cp /opt/output/vdbench-source/* #{@temp_folder} && cd #{@temp_folder} && unzip -q * && ./vdbench -t -s > /dev/null 2>&1")
    if !cmd_run
      `rm -rf #{@temp_folder}; rm -f /tmp/parmfile`
      err_msg "The VDBENCH Zip File is NOT Valid, Please Replace the vdbench zip file in /opt/output/vdbench-source and Make sure it's the only file in this directory!"
    end
    if !$easy_run
      Dir.foreach($self_defined_param_file_path) do |item|
        next if item == '.' or item == '..'
        cmd_run = system("cd #{@temp_folder} && ./vdbench -s -f #{$self_defined_param_file_path}/#{item} > /dev/null 2>&1")
        if !cmd_run
          `rm -rf #{@temp_folder}; rm -f /tmp/parmfile`
          err_msg "The VDBENCH workload profile #{item} is not defined correctly, please check it!"
        end
        has_sda = system("grep sda #{@temp_folder}output/parmscan.html > /dev/null 2>&1")
        vmdk_num_arr = `cat #{@temp_folder}output/parmscan.html | grep -iE ".* line: .*wd.*sd=" | sed -n 's/^.* line: .*wd.*sd=//p' | cut -d "=" -f1 | rev | cut -d ',' -f2- | awk -F\, '{print NF-1}'`.encode('UTF-8', :invalid => :replace).split("\n")
        for vmdk_num in vmdk_num_arr
          if $number_data_disk < (vmdk_num.to_i + 1)
            `rm -rf #{@temp_folder}; rm -f /tmp/parmfile`
            err_msg "The number of disks defined in #{item} is greater than the number of vmdk per vm defined, please make sure the number of disks defined in workload profile is not greater than the number of vmdks per vm!"
          end
          if $number_data_disk == (vmdk_num.to_i + 1) and !has_sda
            `rm -rf #{@temp_folder}; rm -f /tmp/parmfile`
            err_msg "The disks defined in #{item} should have sda configured because OS disk is the last one"
          end
        end
      end
    end
    `rm -rf #{@temp_folder}; rm -f /tmp/parmfile`
  end
end

prepareLogs
if $tool == "vdbench"
  puts "Validating Vdbench binary and the workload profiles..."
  validate_vdbench_binary
end
if $tool == "fio"
  puts "Validating Greenplum binary and the workload profiles..."
  validate_fio_param
end

validate_if_variable_empty($vc_ip)
validate_if_variable_empty($vc_username)
validate_if_variable_empty($vc_password)
validate_if_variable_empty($dc_name)
validate_if_variable_empty($cluster_name)
validate_if_variable_empty($deploy_on_hosts)
validate_if_variable_empty($datastore_names)
validate_subnets
validate_vc_info
validate_dc_info
validate_cluster_info
validate_host_info if $deploy_on_hosts
validate_rp_info
validate_vm_folder_info
validate_network_info
validate_datastore_info
validate_vsan_info if @has_vsan
validate_misc_info
validate_cluster_connection

if !$easy_run
  validate_if_variable_empty($vm_num)
  validate_vm_conf
  validate_testing_config
else
  puts "Easy RUN Enabled, Skipping Validating VM and Parameter Config..."
end

puts "------------------------------------------------------------------------------"
puts "All the config has been validated, please go ahead to kick off testing"
puts "------------------------------------------------------------------------------"

if @warning_msg != ""
  puts "Warning:"
  puts "------------------------------------------------------------------------------"
  @warning_msg.split("\n").each do |line|
    puts line
  end
end
