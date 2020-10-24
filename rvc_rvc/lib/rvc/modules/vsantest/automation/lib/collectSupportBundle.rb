#!/usr/bin/ruby
require_relative "util.rb"
require_relative "rvc-util.rb"
require 'fileutils'

@hosts_list = []
@vsan_clusters = _get_all_vsan_clusters
if not @vsan_clusters.empty?
  @vsan_clusters.each do |vsan_cluster|
    @hosts_list = @hosts_list | _get_hosts_list(vsan_cluster)
  end
else
  puts "vSAN not enabled!", @collect_support_bundle_log
  exit(255)
end

@dest_folder = "#{ARGV[0]}/vm-support-bundle"
@esxi_local_folder = "/tmp/hcibench_vm_support_bundle"

`mkdir -p #{@dest_folder}`

@vm_support_manifest_template = "/opt/automation/lib/vsan-perfsvc-stats-hcibench.mfx.template"
@vm_support_manifest_script = "/opt/automation/lib/vsan-perfsvc-stats-hcibench.mfx"

@collect_support_bundle_log = "#{$log_path}/supportBundleCollect.log"
@failure = false

start_time = ARGV[1] || ARGV[0].split('-')[-1].to_i
end_time = ARGV[2] || File.mtime("#{ARGV[0]}-res.txt").to_i

@update_start_time = "sed -i 's/START_TIME/#{start_time}/g' #{@vm_support_manifest_script}"
@update_end_time = "sed -i 's/END_TIME/#{end_time}/g' #{@vm_support_manifest_script}"

@cmd_delete_manifest = "rm -f /etc/vmware/vm-support/vsan-perfsvc-stats-hcibench.mfx"

def run_cmd(host)
  `sed -i '/#{host} /d' /root/.ssh/known_hosts`
  if ssh_valid(host, $host_username, $host_password)
    puts "Uploading VM Support manifest to #{host}",@collect_support_bundle_log
    scp_item(host,$host_username,$host_password, @vm_support_manifest_script,"/etc/vmware/vm-support")

    puts "Downloading bundle from #{host}...", @collect_support_bundle_log
    `wget --output-document "#{@dest_folder}/#{host}-vm-support-bundle.tgz" --no-check-certificate --user '#{$host_username}' --password '#{$host_password}' https://#{host}/cgi-bin/vm-support.cgi?manifests=Storage:VSANPerfHcibench%20Storage:VSANMinimal`

    puts "Clean up manifest on #{host}", @collect_support_bundle_log
    ssh_cmd(host,$host_username,$host_password,@cmd_delete_manifest)

  else
    puts "Unable to SSH to #{host}",@collect_support_bundle_log
    @failure = true
  end
end

puts "Generating manifest file",@collect_support_bundle_log
FileUtils.cp @vm_support_manifest_template, @vm_support_manifest_script

puts "Updating the time range",@collect_support_bundle_log
system(@update_start_time)
system(@update_end_time)

tnode = []
@hosts_list.each do |s|
  tnode << Thread.new{run_cmd(s)}
end
tnode.each{|t|t.join}

`rm -f #{@vm_support_manifest_script}`

if @failure
  exit(250)
else
  exit
end