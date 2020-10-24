#!/usr/bin/ruby
require_relative "rvc-util.rb"
require_relative "util.rb"

@folder_path_escape = _get_folder_path_escape[0]
@vm_cleanup_log = "#{$log_path}/vm-cleanup.log"
begin
	puts `rvc #{$vc_rvc} --path #{@folder_path_escape} -c "kill *" -c 'exit' -q`,@vm_cleanup_log
	puts `rvc #{$vc_rvc} --path #{@folder_path_escape} -c "destroy ." -c 'exit' -q 2> /dev/null`,@vm_cleanup_log
rescue Exception => e
	puts "dont worry, nothing critical",@vm_cleanup_log
	puts "#{e.class}: #{e.message}",@vm_cleanup_log
end
