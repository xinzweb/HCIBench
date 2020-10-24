#!/usr/bin/ruby
require_relative "rvc-util.rb"
require_relative "util.rb"

@cl_path_escape = _get_cl_path[1]
@tvm_folder_path_escape = _get_tvm_folder_path_escape[0]
@tvm_cleanup_log = "#{$log_path}/prevalidation/tvm-cleanup.log"
begin
	puts `rvc #{$vc_rvc} --path #{@cl_path_escape} -c "vm.kill 'hosts/*/vms/hci-tvm-*'" -c 'exit' -q`,@tvm_cleanup_log
	puts `rvc #{$vc_rvc} --path #{@tvm_folder_path_escape} -c "destroy ." -c 'exit' -q 2> /dev/null`,@tvm_cleanup_log
rescue Exception => e
	puts "dont worry, nothing critical"
	puts "#{e.class}: #{e.message}"
end
