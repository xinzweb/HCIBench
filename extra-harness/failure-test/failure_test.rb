require 'yaml'
require_relative '/opt/automation/lib/rvc-util.rb'

@sleep_after_vmotion = 0
@times = 6

@hosts_list = _get_hosts_list
host_entry = YAML.load_file("./servers.yml")
@idrac_username = host_entry['idrac_username']
@idrac_password = host_entry['idrac_password']
@vm_prefix = ""
@host_vms_map = {}
@srcHost = ""
#prepare host=>[vm1,vm2] map
@hosts_list.each do |host|
  vms = `rvc #{$vc_rvc} -c "find #{$cl_path_escape}/hosts/#{host}/vms" -c "exit" -q | awk -F " " '{print $NF}'`.split("\n")
  @host_vms_map[host] = vms
end

def captureVsanStatus
  puts "Getting resync status"
  print `rvc #{$vc_rvc} -c "vsan.resync_dashboard #{$cl_path_escape}" -c "exit" -q`
end

def resyncFinished
  remainData = `rvc #{$vc_rvc} -c "vsan.resync_dashboard #{$cl_path_escape}" -c "exit" -q | grep Total | awk '{print $6}'`.chomp.to_i
  return true if remainData == 0
  return false
end

def startResync
  puts "Start resync"
  puts `rvc #{$vc_rvc} -c "vsan.health.cluster_repair_immediately #{$cl_path_escape}" -c "exit" -q`
end

def migrateVm(vms,srcHost,destHost)
  puts "Dest Host: #{destHost}"
  puts "Moving #{vms.size} VMs:"
  puts vms.join("\n")
  return false if vms == []
  puts `rvc #{$vc_rvc} -c "vm.migrate -o #{$cl_path_escape}/hosts/#{destHost} #{vms.join(' ')}" -c "exit" -q`
  return true
end

def pickSrcHost
  @srcHost = @hosts_list[rand(@hosts_list.size)]
  while @host_vms_map[@srcHost].size == 0
    @srcHost = @hosts_list[rand(@hosts_list.size)]
  end
  return @srcHost
end

for i in 1..@times
  puts "Starts moving VMs"
  puts "Source Host: #{pickSrcHost} with #{@host_vms_map[@srcHost].size} VMs"
  candidate_destHosts = [] 
  while @host_vms_map[@srcHost].size != 0
    if candidate_destHosts == []
      temp_hosts = @hosts_list.clone
      temp_hosts.delete(@srcHost)
      candidate_destHosts = temp_hosts
    end
    puts "Candidate Dest Hosts: #{candidate_destHosts}"
    vms_to_move = rand(@host_vms_map[@srcHost].size) + 1
    vms = @host_vms_map[@srcHost][0...vms_to_move]
    destHost = candidate_destHosts[rand(candidate_destHosts.size)]
    if migrateVm(vms,@srcHost,destHost)
      @host_vms_map[@srcHost] -= vms
      vms.each do |vm|
	vm.gsub!("/#{@srcHost}/","/#{destHost}/")
      end
      @host_vms_map[destHost] += vms
      candidate_destHosts.delete(destHost)
    end
  end
  sleep(@sleep_after_vmotion) if @sleep_after_vmotion != 0
  idrac = host_entry[@srcHost]
  `sshpass -p '#{@idrac_password}' ssh -o "StrictHostKeyChecking no" #{@idrac_username}@#{idrac} "racadm serveraction hardreset"`
  puts "rebooting Host #{@srcHost}, wait for 5 mins first"
  sleep(300)
  while `rvc #{$vc_rvc} -c "info #{$cl_path_escape}/hosts/#{@srcHost}" -c "exit" -q | grep "connection state" | awk -F " " '{print $NF}'`.chomp != "connected"
    puts "Host not coming back, sleeping 120s"
    sleep(120)
  end
  captureVsanStatus
  startResync
  while not resyncFinished
    puts "Still resyncing data, check back in 60s"
    sleep(60)
  end
end
