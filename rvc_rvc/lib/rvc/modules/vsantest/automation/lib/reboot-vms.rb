#!/usr/bin/ruby
require 'timeout'
require_relative "rvc-util.rb"

@folder_path_escape = _get_folder_path_escape[0]
@reboot_log = "#{$log_path}/reboot.log"

begin
  Timeout::timeout(300) do
    puts `rvc #{$vc_rvc} --path #{@folder_path_escape} -c "vm.reboot_guest #{$vm_prefix}-*" -c "vm.ip #{$vm_prefix}-*" -c 'exit' -q`, @reboot_log
  end
rescue Timeout::Error => e
  puts "Client VMs failed to get IPs", @reboot_log
end
