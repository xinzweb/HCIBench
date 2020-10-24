require 'yaml'
require 'fileutils'
require 'timeout'
require 'shellwords'
require 'find'
require_relative "util.rb"
require_relative "rvc-util.rb"

@vm_health_check_file = "#{$log_path}/vm-health-check.log"
@status_log = "#{$log_path}/test-status.log"
@folder_path_escape = _get_folder_path_escape[0]
@retry_time = 5

class Numeric
  Alpha26 = ("a".."z").to_a
  def alph
    return "" if self < 1
    s, q = "", self
    loop do
      q, r = (q - 1).divmod(26)
      s.prepend(Alpha26[r])
      break if q.zero?
    end
    s
  end
end

def failure_handler(what_failed)
  puts "[ERROR] #{what_failed}",@vm_health_check_file
  puts "[ERROR] Existing VMs not Compatible",@vm_health_check_file
  puts "ABORT: VMs are not existing or Existing VMs are not Compatible",@vm_health_check_file
  exit(255)
end

puts "Checking Existing VMs...",@status_log
#Check vm folder
puts 'Verifying If Folder Exists...',@vm_health_check_file
if !system(%{rvc #{$vc_rvc} --path #{@folder_path_escape} -c 'exit' -q > /dev/null 2>&1})
  failure_handler "No VM Folder Found"
else
  puts 'Folder Verified...',@vm_health_check_file
end
puts "Moving all vms to the current folder",@vm_health_check_file
puts `rvc #{$vc_rvc} --path #{@folder_path_escape} -c "mv temp/* ." -c 'exit' -q`,@vm_health_check_file

#How many VMs actually in the folder
@actual_vm_num = `rvc #{$vc_rvc} --path #{@folder_path_escape} -c "vsantest.perf.get_vm_count #{$vm_prefix}-*" -c 'exit' -q`.to_i

#Check Number of VMs
if ($vm_num > @actual_vm_num) or `rvc #{$vc_rvc} --path #{@folder_path_escape} -c "ls" -c 'exit' -q`.encode('UTF-8', :invalid => :replace).chomp =~ /no matches/
  failure_handler "Not Enough VMs Deployed"
else
  puts "There are #{@actual_vm_num} VMs in the Folder, #{$vm_num} out of #{@actual_vm_num} will be used", @vm_health_check_file
end

#Check VMs' resource info
vms_resource_map = eval(`rvc #{$vc_rvc} --path #{@folder_path_escape} -c "vsantest.perf.get_vm_resource_info #{$vm_prefix}-*" -c 'exit' -q`.encode('UTF-8', :invalid => :replace).chomp)
puts `rvc #{$vc_rvc} --path #{@folder_path_escape} -c 'mv temp/* .' -c 'mkdir temp' -c 'mv #{$vm_prefix}-* temp' -c 'exit' -q`, @vm_health_check_file
puts "Existing VMs info\n#{vms_resource_map}", @vm_health_check_file

$datastore_names.each do |datastore|
  good_vms = []
  vm_resouce = vms_resource_map.clone
  vm_resouce.keys.each do |vm|
    vm_cpu = vm_resouce[vm][0]
    vm_ram = vm_resouce[vm][1]
    nt_name = vm_resouce[vm][2]
    ds_name = vm_resouce[vm][3]
    if vm_cpu == $num_cpu and vm_ram == $size_ram and nt_name == $network_name and datastore == ds_name
      vm_move = Shellwords.escape(%{temp/#{vm.gsub('"','\"')}})
      puts `rvc #{$vc_rvc} --path #{@folder_path_escape} -c "mv #{vm_move} ." -c 'exit' -q`,@vm_health_check_file
      vms_resource_map.delete(vm)
      good_vms << vm
      break if good_vms.size == $vms_perstore
    end
  end
  failure_handler "Not enough proper VMs in #{datastore}" if good_vms.size < $vms_perstore
end

#Reboot all VMs
begin
  Timeout::timeout(720) do
    puts "Rebooting All the Client VMs...",@vm_health_check_file
    `rvc #{$vc_rvc} --path #{@folder_path_escape} -c "vm.reboot_guest #{$vm_prefix}-*" -c "vm.ip #{$vm_prefix}-*" -c 'exit' -q`
    puts "All the Client VMs Rebooted, wait 120 seconds...",@vm_health_check_file
    sleep(120)
    puts "Getting all the Client VMs IP...",@vm_health_check_file
    load $getipfile
  end
rescue Timeout::Error => e
  failure_handler "IP Assignment Failed"
end

puts "Verifying all the Client VMs Disks...",@vm_health_check_file

def verifyVm(vm)
  single_vm_health_file = "#{$log_path}/#{vm}-health-check.log"
  puts "=======================================================",single_vm_health_file
  puts "Verifying VM #{vm}...",single_vm_health_file
  #Check VMDKs
  #Check # of VMDKs
  fail = false
  for i in 1..@retry_time
    if !ssh_valid(vm, 'root', 'vdbench')
      puts "VM #{vm} accessbility #{i}th try is failed, sleep for 10s...", single_vm_health_file
      fail = true
      sleep(10)
    else
      fail = false
      break
    end
  end

  failure_handler "VM #{vm} Not Accessible" if fail
  @num_disk_in_vm = ssh_cmd(vm,'root','vdbench','ls /sys/block/ | grep "sd" | wc -l').chomp.to_i - 1

  if @num_disk_in_vm < $number_data_disk
    failure_handler "Too Many Data Disk Specified"
  else
    puts "There are #{@num_disk_in_vm} Data Disks in VM #{vm}",single_vm_health_file
  end
  #Check size of VMDKs
  for vmdk_index in 1..$number_data_disk
    @data_disk_name = "sd" + vmdk_index.alph
    @sectors_per_vmdk = ssh_cmd(vm,'root','vdbench',"cat /sys/block/#{@data_disk_name}/size").to_i
    if @sectors_per_vmdk/(2*1024*1024) != $size_data_disk
      failure_handler "Data Disk Size Mis-match"
    else
      puts "The #{vmdk_index}/#{$number_data_disk} Data Disk size is #{$size_data_disk}GB", single_vm_health_file
    end
  end

  @test_vdbench_binary_cmd = "test -f /root/vdbench/vdbench && echo $?"
  @test_fio_binary_cmd = "test -f /root/fio/fio && echo $?"
  return_code = ssh_cmd(vm,'root','vdbench', @test_fio_binary_cmd)
  if return_code == ""
    puts "Fio binary does not exist, upload it to client VM #{vm}", single_vm_health_file
    fio_file = "#{$fio_source_path}/fio"
    scp_item(vm,'root','vdbench',fio_file,"/root/fio")

    return_code = ssh_cmd(vm,'root','vdbench', @test_fio_binary_cmd)
    if return_code == ""
      failure_handler "Can not find Fio binary"
    end
  end

  #Check vdbench binary
  if $tool == "vdbench"
    return_code = ssh_cmd(vm,'root','vdbench', @test_vdbench_binary_cmd)
    if return_code == ""
      puts "Vdbench binary does not exist, upload it to client VM #{vm}",single_vm_health_file
      ssh_cmd(vm,'root','vdbench','rm -rf /root/vdbench ; mkdir -p /root/vdbench')
      vdbench_file = Find.find($vdbench_source_path).select {|path| path if path =~ /^.*.zip$/}[0]
      scp_item(vm,'root','vdbench',vdbench_file,"/root/vdbench")
      ssh_cmd(vm,'root','vdbench','cd /root/vdbench ; unzip -q *.zip')

      return_code = ssh_cmd(vm,'root','vdbench',@test_vdbench_binary_cmd)
      if return_code == ""
        failure_handler "Can not find Vdbench binary"
      end
    end
  end
  puts "VM #{vm} Verified.", @vm_health_check_file
end

vms = _ssh_to_vm
tnode = []
vms.each do |s|
  tnode << Thread.new{verifyVm(s)}
end
tnode.each{|t|t.join}

puts "DONE: VMs are healthy and could be reused for I/O testing",@vm_health_check_file