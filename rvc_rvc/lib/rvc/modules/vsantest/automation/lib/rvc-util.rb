require 'yaml'
require 'fileutils'
require 'resolv'
require "json"
require 'shellwords'
require 'ipaddr'
require "cgi"
require_relative 'ossl_wrapper'
require_relative 'util.rb'

# Load the OSSL configuration file
ossl_conf = '../conf/ossl-conf.yaml'

$basedir=File.dirname(__FILE__)
entry = YAML.load_file("#$basedir/../conf/perf-conf.yaml")
#Param Def
$ip_prefix = entry["static_ip_prefix"]
$ip_Address = `ifconfig eth0 2>/dev/null|awk '/inet addr:/ {print $2}'|sed 's/addr://'`.chomp
$docker_ip = `ifconfig docker0 2>/dev/null|awk '/inet addr:/ {print $2}'|sed 's/addr://'`.chomp
$vc_ip = entry["vc"]

begin
  Gem.load_yaml
  osc = YAML.load_file(File.join($basedir, ossl_conf)).each_with_object({}) { |(k, v), m| m[k.to_sym] = v }
rescue Errno::ENOENT
  STDERR.puts "Could not open ossl configuration file: #{ossl_conf} error: file does not exist"
  exit(1)
rescue StandardError => e
  STDERR.puts "Culd not open ossl configuration file: #{ossl_conf} error: #{e}"
  exit(1)
end

vcp = entry["vc_password"]
if vcp
  begin
    osw = OSSLWrapper.new(osc)
    $vc_password = vcp.nil? || vcp.empty? ? '' : osw.decrypt(vcp)
  rescue StandardError => e
    STDERR.puts "Could not decrypt vCenter Password: Please re-save the vCenter Password.\nError: #{e}"
    exit(1)
  end
else
  $vcp_password = ''
end

$clear_cache = entry["clear_cache"]
$vsan_debug = entry["vsan_debug"]

hp = entry["host_password"]
if $clear_cache or $vsan_debug
  if hp
    begin
      osw = OSSLWrapper.new(osc)
      $host_password = hp.nil? || hp.empty? ? '' : osw.decrypt(hp)
    rescue StandardError => e
      STDERR.puts "Could not open decrypt Host Password: Please re-save the Host Password.\nError: #{e}"
      exit(1)
    end
  else
    $host_password = ''
  end
end

$vc_username = entry["vc_username"]
$easy_run = entry["easy_run"]
$dc_name = entry["datacenter_name"].gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$cluster_name = entry["cluster_name"].gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$storage_policy = (entry["storage_policy"] || "").gsub('\\', '\\\\\\').gsub('"', '\"')
$resource_pool_name = (entry["resource_pool_name"] || "" ).gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$resource_pool_name_escape = Shellwords.escape((entry["resource_pool_name"] || "" ).gsub("%","%25").gsub("/","%2f").gsub("\\","%5c"))
$fd_name = entry["vm_folder_name"] || ""
$vm_folder_name = Shellwords.escape(entry["vm_folder_name"] || "")
$network_name = (entry["network_name"] || "VM Network").gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$datastore_names = entry["datastore_name"].map!{|ds|ds.gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")}
$deploy_on_hosts = entry["deploy_on_hosts"]
$tool = entry["tool"]
$vm_prefix = entry["vm_prefix"] || $tool
$tvm_prefix = "hci-tvm"
$folder_name = "#{$vm_prefix}-#{$cluster_name}-vms".gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$tvm_folder_name = "#{$tvm_prefix}-#{$cluster_name}-vms".gsub("%","%25").gsub("/","%2f").gsub("\\","%5c")
$all_hosts = entry["hosts"]
$host_username = entry["host_username"]
$vm_num = entry["number_vm"]
$tvm_num = 0
$num_cpu = entry["number_cpu"] || 4
$size_ram = entry["size_ram"] || 8
$number_data_disk = entry["number_data_disk"]
$size_data_disk = entry["size_data_disk"]
$self_defined_param_file_path = entry["self_defined_param_file_path"]
$warm_up_disk_before_testing = entry["warm_up_disk_before_testing"]
$testing_duration = entry["testing_duration"]
$static_enabled = entry["static_enabled"]
$output_path = entry["output_path"]
$output_path_dir = "/opt/output/results/" + $output_path
$reuse_vm = entry["reuse_vm"]
$cleanup_vm = entry["cleanup_vm"]
$workloads = entry["workloads"] || ["4k70r"]

#File path def
$allinonetestingfile = "#{$basedir}/all-in-one-testing.rb"
$cleanupfile = "#{$basedir}/cleanup-vm.rb"
$cleanuptvmfile = "#{$basedir}/cleanup-tvm.rb"
$cleanupinfolderfile = "#{$basedir}/cleanup-vm-in-folder.rb"
$credentialconffile = "#{$basedir}/../conf/credential.conf"
$deployfile = "#{$basedir}/deploy-vms.rb"
$deploytvmfile = "#{$basedir}/deploy-tvm.rb"
$dropcachefile = "#{$basedir}/drop-cache.rb"
$easyrunfile = "#{$basedir}/easy-run.rb"
$getipfile = "#{$basedir}/get-vm-ip.rb"
$gettvmipfile = "#{$basedir}/get-tvm-ip.rb"
$getxlsvdbenchfile = "#{$basedir}/get-xls-vdbench.rb"
$getxlsfiofile = "#{$basedir}/get-xls-fio.rb"
$getcpuusagefile = "#{$basedir}/getCpuUsage.rb"
$getramusagefile = "#{$basedir}/getRamUsage.rb"
$getvsancpuusagefile = "#{$basedir}/getPCpuUsage.rb"
$healthfile = "#{$basedir}/vm-health-check.rb"
$testfile = "#{$basedir}/io-test.rb"
$vmlistfile = "#{$basedir}/../tmp/vm.yaml"
$tvmlistfile = "#{$basedir}/../tmp/tvm.yaml"
$warmupfile = "#{$basedir}/disk-warm-up.rb"
$warmuptempfile = "#{$basedir}/../tmp/warmedup.tmp"
$parsefiofile = "#{$basedir}/parseFioResult.rb"
$parsevdbfile = "#{$basedir}/parseVdbResult.rb"
$generatereport = "#{$basedir}/generate_report.rb"
$getvsaninfo = "#{$basedir}/get-vsan-info.rb"

#Dir path def
$tmp_path = "#{$basedir}/../tmp/"
$log_path = "#{$basedir}/../logs/"
$vdbench_source_path = "/opt/output/vdbench-source"
$fio_source_path = "/opt/output/fio-source"

$total_datastore = $datastore_names.count
$vc_rvc = Shellwords.escape("#{$vc_username}:#{$vc_password}") + "@#{$vc_ip}" + " -a"
$occupied_ips = []
ENV['GOVC_USERNAME'] = "#{$vc_username}"
ENV['GOVC_PASSWORD'] = "#{$vc_password}"
ENV['GOVC_URL'] = "#{$vc_ip}"
ENV['GOVC_INSECURE'] = "true"
$vm_num = 0 unless $vm_num
$vms_perstore = $vm_num / $total_datastore

$eth1_ip = ""
$vm_yaml_file = "#{$basedir}/../tmp/vm.yaml"
if $static_enabled and $ip_prefix.include? "Customize"
  $starting_static_ip = $ip_prefix.split(" ")[1].split("/")[0]
  $static_ip_size = $ip_prefix.split(" ")[1].split("/")[1]
elsif $static_enabled
  $starting_static_ip = $ip_prefix + ".0.1"
  $static_ip_size = "18"
end

$dc_path = ""
$cl_path = ""
$ip_pool = []
$vsan_perf_diag = false
$cluster_hosts_map = {}
$all_vsan_clusters = []
$all_vsan_lsom_clusters = []
$vsandatastore_in_cluster = {}
$hosts_deploy_list = []
$easy_run_vsan_cluster = ""
#clusters will be running grafana, should be called when cluster has ps enabled and against vsan datastore, if this will be used, local should always be the case
$telegraf_target_clusters_map = {}
#clusters will be running observer, should be called all the time to the local, along with remote vsan ds specified
$observer_target_clusters_arr = [$cluster_name]

def _is_duplicated object_type, object_name, object_parent_path
  object_name_escaped = Shellwords.escape(object_name)
  object_parent_path_escape = Shellwords.escape(object_parent_path)
  types = {"dc" => "d", "rp" => "p", "ds" => "s", "nt" => "n", "fd" => "f", "cl" => "c"}
  count = `govc find -type #{types[object_type]} -name=#{object_name_escaped} #{object_parent_path_escape} | wc -l`.to_i
  return (count > 1)
end

def _get_dc_path
  if $dc_path != ""
    return $dc_path, $dc_path_escape 
  else
    $dc_path = `govc find -type d -name=#{Shellwords.escape($dc_name)}`.chomp
    $dc_path = $dc_path.encode('UTF-8', :invalid => :replace)[1..-1] if $dc_path != ""
    $dc_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}")
  end
  return $dc_path, $dc_path_escape
end

def _get_cl_path(cluster_name = $cluster_name)
  return $cl_path, $cl_path_escape if (cluster_name == $cluster_name) and $cl_path != ""
  $dc_path, $dc_path_escape = _get_dc_path
  @computer_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/computers")
  cl_path = ""
  cl_arr = `rvc #{$vc_rvc} --path #{@computer_path_escape} -c 'find .' -c 'exit' -q`.encode('UTF-8', :invalid => :replace).split("\n")
  cl_arr.each do |cl|
    if cl[/#{Regexp.escape cluster_name}$/] and (cl.partition(' ').last == cluster_name or cl.split('/').last == cluster_name)
      cl_path = "computers/#{cl.partition(' ').last}"
    end
  end
  cl_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/#{cl_path}") if cl_path != ""
  if cluster_name == $cluster_name
    $cl_path = cl_path
    $cl_path_escape = cl_path_escape
  end
  return cl_path, cl_path_escape
end

def _get_folder_path_escape
  $dc_path, $dc_path_escape = _get_dc_path
  folder_path_escape = ""
  folder_path_escape_gsub = ""
  if $fd_name and $fd_name != ""
    folder_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/vms/#{$fd_name}/#{$vm_prefix}-#{$cluster_name}-vms")
    folder_path_escape_gsub = Shellwords.escape("/#{$vc_ip}/#{$dc_path.gsub('"','\"')}/vms/#{$fd_name.gsub('"','\"')}/#{$vm_prefix}-#{$cluster_name.gsub('"','\"')}-vms")
  else
    folder_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/vms/#{$vm_prefix}-#{$cluster_name}-vms")
    folder_path_escape_gsub = Shellwords.escape("/#{$vc_ip}/#{$dc_path.gsub('"','\"')}/vms/#{$vm_prefix}-#{$cluster_name.gsub('"','\"')}-vms")
  end
  return folder_path_escape, folder_path_escape_gsub
end

def _get_tvm_folder_path_escape
  $dc_path, $dc_path_escape = _get_dc_path
  tvm_folder_path_escape = ""
  tvm_folder_path_escape_gsub = ""
  if $fd_name and $fd_name != ""
    tvm_folder_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/vms/#{$fd_name}/#{$tvm_prefix}-#{$cluster_name}-vms")
    tvm_folder_path_escape_gsub = Shellwords.escape("/#{$vc_ip}/#{$dc_path.gsub('"','\"')}/vms/#{$fd_name.gsub('"','\"')}/#{$tvm_prefix}-#{$cluster_name.gsub('"','\"')}-vms")
  else
    tvm_folder_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/vms/#{$tvm_prefix}-#{$cluster_name}-vms")
    tvm_folder_path_escape_gsub = Shellwords.escape("/#{$vc_ip}/#{$dc_path.gsub('"','\"')}/vms/#{$tvm_prefix}-#{$cluster_name.gsub('"','\"')}-vms")
  end
  return tvm_folder_path_escape, tvm_folder_path_escape_gsub
end

#returning all [hosts] in the cluster
def _get_hosts_list(cluster_name = $cluster_name)
  cl_path, cl_path_escape = _get_cl_path(cluster_name) 
  hosts_list = `rvc #{$vc_rvc} --path #{cl_path_escape} -c 'find hosts' -c 'exit' -q | awk -F/ '{print $NF}'`.encode('UTF-8', :invalid => :replace).split("\n")
  return hosts_list
end

#returning [host] for vm to deploy w/o ds restriction
def _get_deploy_hosts_list
  return $hosts_deploy_list if $hosts_deploy_list != []
  if $deploy_on_hosts
    $hosts_deploy_list = $all_hosts 
  else
    $cl_path, $cl_path_escape = _get_cl_path if $cl_path == ""
    $hosts_deploy_list = `rvc #{$vc_rvc} --path #{$cl_path_escape} -c 'find hosts' -c 'exit' -q | awk -F/ '{print $NF}'`.encode('UTF-8', :invalid => :replace).split("\n")
  end
  return $hosts_deploy_list
end

def _get_hosts_list_in_ip(cluster_name = $cluster_name)
  hosts = _get_hosts_list(cluster_name)
  hosts.map!{|host| _get_ip_from_hostname(host)}
  return hosts
end

def _get_hosts_list_by_ds_name(datastore_name)
  ds_path, ds_path_escape = _get_ds_path_escape(datastore_name)
  hosts_list = `rvc #{$vc_rvc} --path #{ds_path_escape} -c 'vsantest.perf.get_hosts_by_ds .' -c 'exit' -q`.encode('UTF-8', :invalid => :replace).split("\n")
  return hosts_list
end

def _get_hosts_list_by_ds_name_in_ip(datastore_name)
  hosts_list = _get_hosts_list_by_ds_name(datastore_name)
  hosts_list.map!{|host| _get_ip_from_hostname(host)}
  return hosts_list
end

def _ssh_to_vm
vm_entry = YAML.load_file("#{$vm_yaml_file}")
vms = vm_entry["vms"]
  for vm in vms
    `sed -i '/#{vm} /d' /root/.ssh/known_hosts`
    `echo -n "#{vm} " >> /root/.ssh/known_hosts`
    `echo -n "\`cat /opt/output/vm-template/vm-key\`\n" >>  /root/.ssh/known_hosts`
  end
  return vms
end

def _get_ds_path_escape(datastore_name)
  $dc_path, $dc_path_escape = _get_dc_path
  ds_path = ""
  ds_path_escape = ""
  datastores_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/datastores")
  ds_arr =  `rvc #{$vc_rvc} --path #{datastores_path_escape} -c 'find .' -c 'exit' -q`.encode('UTF-8', :invalid => :replace).split("\n")
  ds_arr.each do |ds|
    if ds[/#{Regexp.escape datastore_name}$/] and ds.partition(' ').last.gsub(/^.*\//,"") == datastore_name
      ds_path = "datastores/#{ds.partition(' ').last}"
    end
  end
  ds_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/#{ds_path}")
  ds_path = "/#{$vc_ip}/#{$dc_path}/" + ds_path
  return ds_path, ds_path_escape
end

def _is_vsan(datastore_name)
  ds_path, ds_path_escape = _get_ds_path_escape(datastore_name)
  ds_type = `rvc #{$vc_rvc} --path #{ds_path_escape} -c "info ." -c 'exit' -q | grep 'type:' | awk '{print $2}'`.encode('UTF-8', :invalid => :replace).chomp
  return (ds_type == "vsan")
end

def _is_vsan_enabled
  return (_get_vsandatastore_in_cluster != {})
end

def _is_ps_enabled(cluster_name = $cluster_name)
  cl_path, cl_path_escape = _get_cl_path(cluster_name) 
  perf_enabled = `rvc #{$vc_rvc} --path #{cl_path_escape} -c 'vsantest.perf.vsan_cluster_perf_service_enabled .' -c 'exit' -q`
  return (perf_enabled.include? "True")
end

#returning {vsan_ds1 => {"capacity"=>cap,"freeSpace"=>fs,"local"=>true/false}, vsan_ds2 => {"capacity"=>cap,"freeSpace"=>fs,"local"=>true/false}}
def _get_vsandatastore_in_cluster
  return $vsandatastore_in_cluster if $vsandatastore_in_cluster != {}
  $cl_path, $cl_path_escape = _get_cl_path if $cl_path == ""
  cmd_run = `rvc #{$vc_rvc} --path #{$cl_path_escape} -c 'vsantest.perf.find_vsan_datastore .' -c 'exit' -q`.encode('UTF-8', :invalid => :replace).chomp
  begin
    $vsandatastore_in_cluster = eval(cmd_run)
  rescue StandardError => e
    p e.to_s
  ensure
    return $vsandatastore_in_cluster
  end
end

def _get_ip_addr
  return $ip_Address
end

def _is_ip(ip)
  return !!(ip =~ Resolv::IPv4::Regex)
end

def _get_ip_from_hostname(hostname)
  address = ""
  begin
    address = IPSocket.getaddress(hostname)
  rescue Exception => e
    address = "Unresolvable"
  end
  return address
end

def _get_perfsvc_master_node(cluster_name = $cluster_name)
  hosts_list = _get_hosts_list(cluster_name)
  cmd = "python /usr/lib/vmware/vsan/perfsvc/vsan-perfsvc-status.pyc svc_info | grep 'isStatsMaster = true' | wc -l"
  hosts_list.each do |host|
    return host if ssh_valid(host,$host_username,$host_password) and ssh_cmd(host,$host_username,$host_password,cmd).chomp == "1"
  end
  return ""
end

def _set_perfsvc_verbose_mode(verbose_mode,cluster_name = $cluster_name)
  cl_path, cl_path_escape = _get_cl_path(cluster_name)
  `rvc #{$vc_rvc} --path #{cl_path_escape} -c 'vsantest.perf.vsan_cluster_perfsvc_switch_verbose . #{verbose_mode}' -c 'exit' -q`
  return ($?.exitstatus == 0)
end

# get ip pool if using static, otherwise return []
# only add the ips not being occupied
def _get_ip_pools
  return [] if not $static_enabled
  return $ip_pool if $ip_pool != []
  ip_range = IPAddr.new("#{$starting_static_ip}/#{$static_ip_size}")
  begin_ip = IPAddr.new($starting_static_ip)
  ips = []
  ip_required = [_get_num_of_tvm_to_deploy,_get_num_of_vm_to_deploy].max + 1 
  while ips.size < ip_required and ip_range.include? begin_ip do
    find_ip_threads = []
    count = ips.size
    temp_ip_arr = []
    while count < ip_required and ip_range.include? begin_ip do
      temp_ip_arr << begin_ip.to_s
      begin_ip = begin_ip.succ()
      count += 1
    end
    temp_ip_arr.each do |ip_to_s|
      find_ip_threads << Thread.new{
        if not system("arping -q -I eth1 -c 5 #{ip_to_s}") # ip available
          $occupied_ips.delete(ip_to_s) if $occupied_ips.include? ip_to_s
          ips << ip_to_s if not ips.include? ip_to_s
        else #ip occupied
          $occupied_ips << ip_to_s if not $occupied_ips.include? ip_to_s
        end
      } 
    end
    find_ip_threads.each{|t|t.join}
  end
  ips = ips.sort_by{|s| s.split(".")[-1].to_i}
  $eth1_ip = ips[0] if ips[0]  
  $ip_pool = ips[1..-1]
  return $ip_pool
end

#despite if any ip is occupied, whether the subnet itself is big enough
def _range_big_enough
  ip_range = IPAddr.new("#{$starting_static_ip}/#{$static_ip_size}")
  temp_ip = IPAddr.new($starting_static_ip)
  ip_required = [_get_num_of_tvm_to_deploy,_get_num_of_vm_to_deploy].max + 1
  for i in 1..ip_required 
    return false if not ip_range.include? temp_ip
    temp_ip = temp_ip.succ()
  end
  return true
end

#Would only called by pre-validation
def _get_num_of_tvm_to_deploy
  return $tvm_num if $tvm_num != 0
  $tvm_num = _get_deploy_hosts_list.size  
  return $tvm_num
end

#Would only called by pre-validation, 
def _get_num_of_vm_to_deploy
  return $vm_num if not $easy_run
  num_of_dg = 0
  sum_stats = _get_vsan_disk_stats(_pick_vsan_cluster_for_easy_run)[1]
  sum_stats.each do |stat|
    num_of_dg = stat.scan(/\d/).join.to_i if stat.include? "Total_DiskGroup_Number" 
  end
  $cl_path, $cl_path_escape = _get_cl_path if $cl_path == ""
  witness = `rvc #{$vc_rvc} --path #{$cl_path_escape} -c 'vsantest.vsan_hcibench.cluster_info .' -c 'exit' -q | grep -E "^Witness Host:"`.chomp
  num_of_dg -= 1 if witness != ""
  $vm_num = num_of_dg * 2 * $total_datastore
  return $vm_num 
end

def _pick_vsan_cluster_for_easy_run
  return $easy_run_vsan_cluster if $easy_run_vsan_cluster != ""
  vsan_datastores = _get_vsandatastore_in_cluster
  vsan_datastore_names = vsan_datastores.keys & $datastore_names
  remote_cluster = []
  vsan_datastore_names.each do |vsan_datastore_name|
    if vsan_datastores[vsan_datastore_name]["local"]
      $easy_run_vsan_cluster = _get_vsan_cluster_from_datastore(vsan_datastore_name)
      return $easy_run_vsan_cluster
    else
      remote_cluster << _get_vsan_cluster_from_datastore(vsan_datastore_name)
    end
  end
  $easy_run_vsan_cluster = remote_cluster[0]
  return $easy_run_vsan_cluster
end

def _is_ds_local_to_cluster(datastore_name)
  $cl_path, $cl_path_escape = _get_cl_path
  ds_path, ds_path_escape = _get_ds_path_escape(datastore_name)
  cluster_id = `rvc #{$vc_rvc} --path #{$cl_path_escape} -c 'vsantest.perf.get_cluster_id .' -c 'exit' -q`.chomp
  datastore_container_id = `rvc #{$vc_rvc} --path #{ds_path_escape} -c 'vsantest.perf.get_vsan_datastore_container_id .' -c 'exit' -q`.chomp
  return (cluster_id == datastore_container_id)
end

# get the owner cluster of the datastore
def _get_vsan_cluster_from_datastore(datastore_name)
  ds_path, ds_path_escape = _get_ds_path_escape(datastore_name)
  cluster_name = `rvc #{$vc_rvc} --path #{ds_path_escape} -c 'vsantest.perf.get_vsan_owner_cluster_from_datastore .' -c 'exit' -q`.chomp
  return cluster_name
end

# get compliant [ds] of the storage policy
def _get_compliant_datastore_ids_escape(storage_policy = $storage_policy)
  $dc_path, $dc_path_escape = _get_dc_path
  get_compliant_datastore_ids_escape = Shellwords.escape(%{vsantest.perf.get_compliant_datastore_by_policy_name . "#{storage_policy}"})
  compliant_ds_ids = `rvc #{$vc_rvc} --path #{$dc_path_escape} -c #{get_compliant_datastore_ids_escape} -c 'exit' -q`.chomp
  return [] if compliant_ds_ids == "Cant find the storage policy #{storage_policy}" or compliant_ds_ids == "Cant find compliant datastore for policy #{storage_policy}"
  return compliant_ds_ids.split("\n")
end

# return datastore ref_id
def _get_ds_id_by_name(datastore_name)
  ds_path, ds_path_escape = _get_ds_path_escape(datastore_name)
  ds_id = `rvc #{$vc_rvc} --path #{ds_path_escape} -c 'vsantest.perf.get_datastore_id .' -c 'exit' -q`.chomp
  return ds_id
end

#clusters have vsan datastores mounted to testing cluster and those datastores are used for testing
#may not include the local cluster if only testing against remote datastores
#this would be only useful for wb clear
def _get_all_vsan_lsom_clusters
  return $all_vsan_lsom_clusters if $all_vsan_lsom_clusters != []
  vsan_datastores = _get_vsandatastore_in_cluster
  if vsan_datastores == {}
    p "vSAN is not enabled!"
    return []
  else
    vsan_datastore_names = vsan_datastores.keys & $datastore_names
    if not vsan_datastore_names.empty?
      vsan_datastore_names.each do |vsan_datastore_name|
        $all_vsan_lsom_clusters = $all_vsan_lsom_clusters | [_get_vsan_cluster_from_datastore(vsan_datastore_name)]
      end
    end
  end
  return $all_vsan_lsom_clusters
end

#clusters have vsan datastores mounted to testing cluster and those datastores are used for testing
#also must include the local cluster
#this would be only useful for all the cases except wb clear
def _get_all_vsan_clusters
  return $all_vsan_clusters if $all_vsan_clusters != []
  vsan_datastores = _get_vsandatastore_in_cluster
  if vsan_datastores == {}
    p "vSAN is not enabled!"
    return []
    #vsan is enabled, pass over all the clusters with vsan enabled
    #if remote cluster is included, it must have remote ds for testing
    #local cluster is automatically included even w/o any vsan ds being tested
  else
    $all_vsan_clusters = [$cluster_name]
    vsan_datastore_names = vsan_datastores.keys & $datastore_names
    #we at least have one vsan ds to test
    if not vsan_datastore_names.empty?
      $vsan_perf_diag = true
      vsan_datastore_names.each do |vsan_datastore_name|
        $all_vsan_clusters =  $all_vsan_clusters | [_get_vsan_cluster_from_datastore(vsan_datastore_name)]
      end
    end
  end
  return $all_vsan_clusters
end

#returning policy_name, rules in []
def _get_vsan_default_policy(datastore_name)
  ds_path, ds_path_escape = _get_ds_path_escape(datastore_name)
  default_policy = `rvc #{$vc_rvc} --path #{ds_path_escape} -c "vsantest.spbm_hcibench.get_vsandatastore_default_policy ." -c 'exit' -q`.encode('UTF-8', :invalid => :replace).split("\n")
  rule_start_pos = 0
  policy_name = ""
  default_policy.each_with_index do |line,index|
    policy_name = line.split(" ")[1..-1].join(' ') if line.match "^Name: .*"
    rule_start_pos = index + 1 if line.match "^Rule-Sets:"
  end
  return policy_name,default_policy[rule_start_pos..-1]
end

#returning rules of the storage policy in []
def _get_storage_policy_rules(storage_policy = $storage_policy)
  rules = []
  $dc_path, $dc_path_escape = _get_dc_path
  get_rules_escape = Shellwords.escape(%{vsantest.perf.get_policy_rules_by_name . "#{storage_policy}"})
  rules = `rvc #{$vc_rvc} --path #{$dc_path_escape} -c #{get_rules_escape} -c 'exit' -q | grep -E "^Rule-Sets:" -A 100`.encode('UTF-8', :invalid => :replace).split("\n")
  return rules
end

#returning vsan disk stats detail table stats, sum stats
def _get_vsan_disk_stats(cluster_name = $cluster_name)
  cl_path, cl_path_escape = _get_cl_path(cluster_name)
  stats = `rvc #{$vc_rvc} --path #{cl_path_escape} -c 'vsantest.vsan_hcibench.disks_stats .' -c 'exit' -q`.chomp.split("\n")
  first_pos = 0
  last_pos = 0
  stats.each_with_index do |stat,index|
    if first_pos == 0 and stat.include? "-+-"
      first_pos = index
    end
    last_pos = index if stat.include? "-+-"
  end
  #stats[first_pos..last_pos]: detail disks stats in table
  #stats[(last_pos+1)..-1]: summariezed disks stats info
  return stats[first_pos..last_pos],stats[(last_pos+1)..-1]
end

# returning dd/c scope, af/hybrid
def _get_vsan_type(cluster_name = $cluster_name)
  cl_path, cl_path_escape = _get_cl_path(cluster_name)
  vsan_type = `rvc #{$vc_rvc} --path #{cl_path_escape} -c 'vsantest.vsan_hcibench.vsan_type .' -c 'exit' -q`.chomp.split("\n")
  dd_scope = "0"
  type = "Hybrid"
  if vsan_type.size == 2
    dd_scope = vsan_type[0].split(" ")[1]
    type = vsan_type[1].split(" ")[1]
  end
  return dd_scope,type
end

def _get_cluster_hosts_map_from_file(test_case_path)
  cluster_hosts_map = {}
  Dir.entries(test_case_path).select {|entry| File.directory? File.join(test_case_path,entry) and !(entry =='.' || entry == '..') and entry =~ /iotest-/}.each do |ioFolder|
    filename = test_case_path + "/#{ioFolder}/cluster_hosts_map.cfg"
    if File.exist? filename
      file_data = File.open(filename).read
      cluster_hosts_map = eval(file_data)
    else
      cluster_hosts_map = _get_cluster_hosts_map
      File.open(filename, "w") { |f| f.write cluster_hosts_map.to_s }
    end
  end
  return cluster_hosts_map
end

#returning has {cluster1 => [hosts...], cluster2 => [hosts...]}
def _get_cluster_hosts_map
  return $cluster_hosts_map if $cluster_hosts_map != {}
  @vsan_clusters = _get_all_vsan_clusters
  if not @vsan_clusters.empty?
    @vsan_clusters.each do |vsan_cluster|
      $cluster_hosts_map[vsan_cluster] = _get_hosts_list(vsan_cluster)
    end
  else
    $cluster_hosts_map[$cluster_name] = _get_hosts_list
  end
  return $cluster_hosts_map
end

# returning spare resource info of host in [cpu,ram_in_GB]
def _get_host_spare_compute_resource(host)
  $cl_path, $cl_path_escape = _get_cl_path
  host_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/#{$cl_path}/hosts/#{host}")
  resource = []
  resource = `rvc #{$vc_rvc} --path #{host_path_escape} -c 'vsantest.perf.get_host_spare_compute_resource .' -c 'exit' -q`.chomp.split("\n")
  return resource
end

def _get_resource_used_by_guest_vms(host)
  $cl_path, $cl_path_escape = _get_cl_path
  resource_usage = [0,0]
  host_path_escape = Shellwords.escape("/#{$vc_ip}/#{$dc_path}/#{$cl_path}/hosts/#{host}")
  vm_resource = eval(`rvc #{$vc_rvc} --path #{host_path_escape} -c 'vsantest.perf.get_resource_used_by_vms .' -c 'exit' -q`.chomp)
  vm_resource.keys.each do |vm_name|
    if vm_name =~ /^#{$vm_prefix}-/
      resource_usage[0] += vm_resource[vm_name][0]
      resource_usage[1] += vm_resource[vm_name][1]
    end
  end
  return resource_usage
end

# returning datastore capacity and free space
def _get_datastore_capacity_and_free_space(datastore_name)
  ds_path, ds_path_escape = _get_ds_path_escape(datastore_name)
  cap_and_fs = []
  cap_and_fs = `rvc #{$vc_rvc} --path #{ds_path_escape} -c "vsantest.perf.get_datastore_capacity_and_free_space ." -c 'exit' -q`.encode('UTF-8', :invalid => :replace).split("\n")
  return cap_and_fs[0], cap_and_fs[1]
end

def _get_cpu_usage(test_case_path)
  msg = ""
  dir = test_case_path
  _get_cluster_hosts_map
  $cluster_hosts_map.keys.each do |cluster_name|
    if File.directory?(dir)
      Dir.entries(dir).select {|entry| File.directory? File.join(dir,entry) and !(entry =='.' || entry == '..') and entry =~ /iotest-/}.each do |ioFolder|
        jsonFile_list = `find "#{dir}/#{ioFolder}"/jsonstats/pcpu/ -type f -name 'pcpu*' | grep -e "#{$cluster_hosts_map[cluster_name].join('\|')}" | grep -v thumb`
        jsonFile_list = jsonFile_list.split("\n")
        server_resource_usage_arr = []
        jsonFile_list.each do |file|
          jsonFile = open(file)
          json = jsonFile.read
          parsed = JSON.parse(json)
          each_resource_usage_arr = []
          parsed["stats"].each do |vcpu|
            arr = vcpu[1]["usedPct"]["values"]
            avg_each_vcpu = arr.inject{ |sum, el| sum + el }.to_f / arr.size
            each_resource_usage_arr.push(avg_each_vcpu)
          end
          avg_each_test_server = each_resource_usage_arr.inject{ |sum, el| sum + el }.to_f / each_resource_usage_arr.size
          server_resource_usage_arr.push(avg_each_test_server)
        end
        avg_test_case = (server_resource_usage_arr.inject{ |sum, el| sum + el }.to_f / server_resource_usage_arr.size).round(2)
        msg += "#{cluster_name}: #{avg_test_case}%; "
      end
    end
  end
  if msg.count(";") == 1
    return msg.scan(/[0-9]*.[0-9]*%/).join 
  else
    return msg
  end
end

def _get_ram_usage(test_case_path)
  msg = ""
  dir = test_case_path
  _get_cluster_hosts_map
  $cluster_hosts_map.keys.each do |cluster_name|
    if File.directory?(dir)
      Dir.entries(dir).select {|entry| File.directory? File.join(dir,entry) and !(entry =='.' || entry == '..') and entry =~ /iotest-/}.each do |ioFolder|#enter io folder
        jsonFile_list = `find "#{dir}/#{ioFolder}"/jsonstats/mem/ -type f -name 'system*' | grep -e "#{$cluster_hosts_map[cluster_name].join('\|')}"  | grep -v thumb`
        jsonFile_list = jsonFile_list.split("\n")
        server_resource_usage_arr = [] 
        jsonFile_list.each do |file|
          jsonFile = open(file)
          json = jsonFile.read
          parsed = JSON.parse(json)
          each_resource_usage_arr = []
          arr = parsed["stats"]["pctMemUsed"]["values"]
          avg_each_ram = arr.inject{ |sum, el| sum + el }.to_f / arr.size
          each_resource_usage_arr.push(avg_each_ram)
          avg_each_test_server = each_resource_usage_arr.inject{ |sum, el| sum + el }.to_f / each_resource_usage_arr.size
          server_resource_usage_arr.push(avg_each_test_server)
        end
        avg_test_case = (server_resource_usage_arr.inject{ |sum, el| sum + el }.to_f / server_resource_usage_arr.size).round(2)
        msg += "#{cluster_name}: #{avg_test_case}%; "
      end
    end
  end
  if msg.count(";") == 1
    return msg.scan(/[0-9]*.[0-9]*%/).join 
  else
    return msg
  end
end

def _get_vsan_cpu_usage(test_case_path)
  msg = ""
  dir = test_case_path
  _get_cluster_hosts_map
  $cluster_hosts_map.keys.each do |cluster_name|
    if File.directory?(dir)
      pcpu_usage=
      total_pcpu=
      dirName = File.basename(dir)
      Dir.entries(dir).select {|entry| File.directory? File.join(dir,entry) and !(entry =='.' || entry == '..') and entry =~ /iotest-/}.each do |ioFolder|#enter io folder
        jsonFile_list = `find "#{dir}/#{ioFolder}"/jsonstats/pcpu/ -type f -name 'wdtsum-*' | grep -e "#{$cluster_hosts_map[cluster_name].join('\|')}" | grep -v thumb `
        jsonFile_list = jsonFile_list.split("\n")
        file_cpu_usage_arr = [] #each element should be the avg of each server cpu_usage number
        jsonFile_list.each do |file| # get each server's cpu_usage number
          jsonFile = open(file)
          json = jsonFile.read
          begin
            parsed = JSON.parse(json)
          rescue JSON::ParserError => e
            return e
          end
          arr = parsed["stats"]["runTime"]["avgs"]
          avg_of_file = arr.inject { |sum, el| sum + el }.to_f / arr.size * 100
          file_cpu_usage_arr.push(avg_of_file)
        end
        pcpu_usage=file_cpu_usage_arr.inject{ |sum, el| sum + el }.to_f
      end
      Dir.entries(dir).select {|entry| File.directory? File.join(dir,entry) and !(entry =='.' || entry == '..') and entry =~ /iotest-/}.each do |ioFolder|#enter io folder
        jsonFile_list = `find "#{dir}/#{ioFolder}"/jsonstats/pcpu/ -type f -name 'pcpu*' | grep -e "#{$cluster_hosts_map[cluster_name].join('\|')}" | grep -v thumb`
        jsonFile_list=jsonFile_list.split("\n")
        total_num_of_pcpu = [] #each element should be the avg of each server cpu_usage number
        jsonFile_list.each do |file| # get each server's cpu_usage number
          jsonFile = open(file)
          json = jsonFile.read
          parsed = JSON.parse(json)
          total_num_of_pcpu.push(parsed["stats"].size)
        end
        total_pcpu = total_num_of_pcpu.inject{ |sum, el| sum + el }
      end
      msg += "#{cluster_name}: #{(pcpu_usage/total_pcpu).round(2)}%; "
    end
  end
  if msg.count(";") == 1
    return msg.scan(/[0-9]*.[0-9]*%/).join 
  else
    return msg
  end
end
