#!/usr/bin/ruby
require_relative "rvc-util.rb"
require "logger"

logfilepath = "#{$log_path}telegraf.log"
#File.delete(logfilepath) if File.exist?(logfilepath)

log = Logger.new(logfilepath)
log.level = Logger::INFO
conf_path = "/opt/automation/conf/"
conf_file = "telegraf.conf"

#Convert a string to a unicode string.
def convert2unicode(str)
    strNew = ""
    str.split('').each { |c| strNew = strNew + '\\u' + c.ord.to_s(16).rjust(4,'0') }
    return strNew
end

log.info "Config env for govc"
#Set the env virables and Get the cluster path
ENV['GOVC_USERNAME'] = "#{$vc_username}"
ENV['GOVC_PASSWORD'] = "#{$vc_password}"
ENV['GOVC_URL'] = "#{$vc_ip}"
ENV['GOVC_INSECURE'] = "true"
env = `govc env`
lines = env.lines
log.info "govc env is set as: #{lines[0].gsub("\n",",")} #{lines[2].gsub("\n",",")} #{lines[3].gsub("\n", ".")}" if lines.count == 4

clusterpaths = Array[]
clusters = `govc find -type c`
clusters = clusters.split("\n")

cluster_names = $telegraf_target_clusters_map.keys
if cluster_names == []
  log.info "adding local cluster if it has perfsvc enabled"
  #adding local cluster into telegraf, the only req is to have perfsvc enabled
  cluster_names = [$cluster_name] if _is_ps_enabled($cluster_name)
  $datastore_names.each do |datastore_name|
    if _is_vsan(datastore_name) and not _is_ds_local_to_cluster(datastore_name)
      vsan_cluster = _get_vsan_cluster_from_datastore(datastore_name)
      log.info "adding #{vsan_cluster} cluster if it has perfsvc enabled"
      cluster_names << vsan_cluster if _is_ps_enabled(vsan_cluster)
    end
  end
end

clusters.each do |cluster|
  cluster_names.each do |cluster_name|
    clusterpaths.push(cluster) if cluster.include? $dc_name and cluster.include? cluster_name
  end
end

log.info "Discovered #{clusterpaths.length.to_s} cluster path(s): #{clusterpaths}"

if clusterpaths.length == 0
   log.error "No valid cluster path discovered!"
   exit
end
cluster_paths = []
clusterpaths.each{|x| cluster_paths << convert2unicode(x)}
#clusterpaths = clusterpaths[0]
log.info "By default, the paths will be used: #{clusterpaths}"

#Path of the vsphere template file
file_name = "#{conf_path}vsphere_template.conf"

#convert all the chars in the password string to unicodes.
pwd = convert2unicode($vc_password)
dcname = convert2unicode($dc_name)
#clusterpath = convert2unicode(clusterpath)
telegraf_running = `docker ps -a | grep telegraf_vsan | grep Up | wc -l`.chomp

if telegraf_running == "1"
  log.info "Container telegraf_vsan is running, stop it first"
  #Stop all the other telegraf instances if any.
  `ruby ./stop_all_telegraf.rb`
else
  log.info "Container telegraf_vsan is not running"
end

log.info "Generating the config file."
begin
    #set the values such as vc_ip, username, psw in the config file by replacing the keywords in the template.
    text = File.read(file_name)
    if $vsan_debug
        text = text.gsub(/300s/, "60s")
    end
    text = text.gsub(/<vcenter-ip>/, $vc_ip)
    text = text.gsub(/<user>/, $vc_username)
    text = text.gsub(/<pwd>/, pwd)
    text = text.gsub(/<dcname>/, dcname)
    cluster_path_str = ""
    cluster_path_host_str = ""
    cluster_paths.each do |clusterpath|
      cluster_path_str += '"'+clusterpath+'", '
      cluster_path_host_str += '"'+clusterpath+'/**", '
    end
    text = text.gsub(/<clusterpath>/, cluster_path_str)
    text = text.gsub(/<clusterpath-host>/, cluster_path_host_str)

    #Generate the config file
    File.open("#{conf_path}#{conf_file}", "w") {|file| file.puts text }
rescue Exception => e
    log.error "Exception happened: #{e.message}"
    exit
end

begin
    #start container
    `docker start telegraf_vsan`
    _retry = 0
    while _retry < 5
      if `docker ps -a | grep telegraf_vsan | grep Up | wc -l`.chomp == "1"
        log.info "Container telegraf_vsan started"
        break
      else
        log.info "Container telegraf_vsan is not started yet, waiting for 3 seconds and try again"
        sleep(3)
        _retry += 1
      end
    end
    if _retry == 5 and `docker ps -a | grep telegraf_vsan | grep Up | wc -l`.chomp == "0"
      log.error "Container telegraf_vsan could not start"
    end

rescue Exception => e
    log.error "Exception happend: #{e.message}"
    exit
end