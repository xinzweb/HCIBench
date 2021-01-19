#!/bin/env ruby
require 'yaml'
require 'time'
require 'json'
require 'timeout'
require 'net/ssh'
require 'net/scp'
require 'optparse'
require "/opt/automation/lib/util.rb"
require "/opt/automation/lib/rvc-util.rb"

# example 1: just run, no build env
# command : ruby hana_auto.rb "4K Block, Log Volume 5GB, Overwrite" /opt/bca/test --run-only

# example 2: build env and run
# command example 2: ruby hana_auto.rb "4K Block, Log Volume 5GB, Overwrite" /opt/bca/test 


@workload = ARGV[0]

# ARGV[1] output folder path, please use the absolute path.
@outputfolder = ARGV[1]

runonly = false
if ARGV[2] == "--run-only"
	runonly = true
end

# Get the cluster names need to be monitored by the observer.
@observer_clusters = []
$datastore_names.each do |datastore_name|
    @observer_clusters << _get_vsan_cluster_from_datastore(datastore_name)
end

if not File.file?("#{@outputfolder}/hana.log")
    `> #{@outputfolder}/hana.log`
    File.write("#{@outputfolder}/hana.log", "Start Time, Observer PIDs \n", mode: "a")
end

arr_node =[]
@credential = "#{$vc_username}:#{$vc_password}"
@vc = "#{$vc_ip}"
@dc = "#{$dc_name}"
#use the first datastore by default.
@datastore = "#{$datastore_names[0]}"
@prefix = "KAFKA-VM-"
@host_password = "#{$host_password}"
@cluster = "#{$cluster_name}"
@vms_map = {}
@hosts_list = []
@dc_path = "/#{@vc}/#{@dc}"
@cl_path = "/#{@vc}/#{@dc}/computers/#{@cluster}"
@pids = []
@start_time = 0

@vms = {}
@master_ip = ""
@json_temp = "/opt/bca/hana/test.json.template"
@json_new = "/opt/bca/hana/#{@workload.gsub(" ","_").gsub(",","-")}.json"
@json_new_filename = "#{@workload.gsub(" ","_").gsub(",","-")}.json"

def ssh_cmd(host, user, pass, cmd)
    `ssh-keyscan -H "#{host.to_s}" >> ~/.ssh/known_hosts`
    return_value = ""
    begin
      Net::SSH.start( host.to_s, user.to_s, :password => pass.to_s, :number_of_password_prompts => 0 ) do |ssh|
        return_value = ssh.exec!(cmd.to_s)
        ssh.close
      end
    rescue Net::SSH::ConnectionTimeout
      p "Timed out"
    rescue Timeout::Error
      p "Timed out"
    rescue Errno::EHOSTUNREACH
      p "Host unreachable"
    rescue Errno::ECONNREFUSED
      p "Connection refused"
    rescue Net::SSH::AuthenticationFailed
      p "Authentication failure"
    rescue Exception => e
      p "#{e.class}: #{e.message}"
    end
    return return_value
end
def startObserver
    `mkdir -p #{@outputfolder}/observerData`
    @observer_clusters.each { |cluster|
        cl_path = "/#{@vc}/#{@dc}/computers/#{cluster}"
        pid = fork do
            exec("rvc #{@credential}@#{@vc} -c 'vsantest.vsan_hcibench.observer #{cl_path} -m 1 -e #{@outputfolder}/observerData' -c 'exit'")
        end
        @pids << pid
    }
    # get start time
    time = Time.now 
    @start_time = time.to_i
    # line format: pid , current_time
    File.write("#{@outputfolder}/kafka.log", "#{time.to_s}, #{@pids}\n", mode: "a")
end

def stopObserver
    for pid in @pids
        `kill -9 #{pid}`
    end
end

def processStatsfile
    `rvc "#{@credential}"@"#{@vc}" -c 'vsantest.vsan_hcibench.observer_process_statsfile "#{@outputfolder}"/observerData/observer.json "#{@outputfolder}"/observerData' -c 'exit'`
end

def parseVmkstats
    `ruby /opt/automation/lib/collectVmkstats.rb "#{@outputfolder}" "true"`
end

def collectVmkstats
    sleep(1800)
    `ruby /opt/automation/lib/collectVmkstats.rb "#{@outputfolder}" "false"`
    parseVmkstats
end

def collectSupportBundle
    time = Time.now
    stop_time = time.to_i
    `ruby /opt/automation/lib/collectSupportBundle.rb #{@outputfolder} "#{@start_time}" "#{stop_time}"`
end 

def dropCache
    `ruby /opt/automation/lib/drop-cache.rb`
end

def start_hcmt
    `sshpass -p vmware ssh #{@master_ip} "/root/setup/hcmt -t -v -p /root/setup/#{@json_new_filename} > /root/setup/#{@json_new_filename}.test.log 2>&1"`
end

def gather_hcmt_result
    `mkdir -p #{@outputfolder}/hcmt_results/`
    fname = `sshpass -p "vmware" ssh #{@master_ip} "ls /root/setup/*.zip -rt | tail -n 1"`.chomp
    `sshpass -p "vmware" scp #{@master_ip}:#{fname} #{@outputfolder}/hcmt_results/`
    `cd #{@outputfolder}/hcmt_results/; unzip *.zip`
end

def rebuild_env(host,batch)
    cluster = 33
    cluster = 34 if host == 72 or host == 71 or host == 70
    `rvc -a 'administrator@vsphere.local:P@ssw0rd'@10.159.24.1 --path "/10.159.24.1/PRME" -c "vm.clone -p computers/Cluster-#{cluster}/resourcePool -d datastores/vsanDatastore-#{cluster} -o computers/Cluster-#{cluster}/hosts/10.40.192.#{host} vms/sap-temp-#{cluster}/ vms/HANA-#{host}-#{batch}" -c "vm.set_extra_config vms/HANA-#{host}-#{batch} numa.nodeAffinity=#{batch}" -c "vm.on vms/HANA-#{host}-#{batch}" -c "exit"`    
end

def prep_ip
    first = true
    vmsIp = ""
    while vmsIp == ""
        if first
            first = false
        else
            `rvc -a 'administrator@vsphere.local:P@ssw0rd'@10.159.24.1 --path "/10.159.24.1/PRME" -c "vm.reset vms/HANA-*" -c "exit" -q`
        end
        begin
            Timeout.timeout(60) do
                vmsIp = `rvc -a 'administrator@vsphere.local:P@ssw0rd'@10.159.24.1 --path "/10.159.24.1/PRME" -c "vm.ip vms/HANA-*" -c "exit" -q`.chomp.split("\n")
            end
        rescue Timeout::Error => e
            puts e
            vmsIp = ""
        end
    end
    vmsIp.each do |vmIp|
       vmip = vmIp.split(":")[1].strip()
       @vms[vmIp.split(":")[0]] = vmip
       `sshpass -p vmware ssh -o "StrictHostKeyChecking no" #{vmip} "rm -rf /data/*; rm -rf /log/*; exit"`
    end
end

def createNewJson(workload,remote_hana_vm_list)
    
    text = File.read(@json_temp)
    json = JSON.parse(text)
    varibles = json["Variables"]
    plans = json["ExecutionPlan"]
    remote_hana_vm_list_size = remote_hana_vm_list.split(",").size
    varibles.each do |var|
        var["Value"] = remote_hana_vm_list if var["Name"] == "Hosts"
        var["Value"] = ['/data']*remote_hana_vm_list_size if var["Name"] == "DataVolumeHosts"
        var["Value"] = ['/log']*remote_hana_vm_list_size if var["Name"] == "LogVolumeHosts"
    end
    new_execPlans = []
    new_execVariants = []
    plans.each do |plan|
        found = false
        execVariants = plan["ExecutionVariants"]
        id = plan["ID"]
        execVariants.each do |execVariant|
            if execVariant["Description"] == workload
                new_execVariants << execVariant
                new_execPlans << {"ID" => id, "Note" => workload,"ExecutionVariants" => new_execVariants}
                found = true
                break
            end
        end
        break if found
    end
    new_json = {"Variables" => varibles, "ExecutionPlan" => new_execPlans}.to_json
    File.open(@json_new, "w") {|file| file.puts new_json }
end

def prep_json(workload)
    ips = @vms.values[1..-1].join(", ") # to replace --hots--
    createNewJson(workload,ips)
    @master_ip = @vms.values[0]
    puts "#{@master_ip} is master"
    `sshpass -p vmware scp #{@json_new} #{@master_ip}:/root/setup`
end

hosts = [65,66,67,70,71,72]
batch = [0,1]

# step 1: cloning the VMs from the template and deploy CRDB
if not runonly
    tnode = []
    hosts.each do |host|
        batch.each do |bt|
            tnode << Thread.new{rebuild_env(host,bt)}
        end
    end
    tnode.each{|t|t.join}
end

prep_ip

prep_json(@workload)

# step 3, drop cache
puts Time.now.to_s + ": Droping the cache..."
dropCache
# step 4 , start kafka jobs for all the VMs.
puts Time.now.to_s +  ": Starting HCMT benchmark..."
tnode = []
tnode << Thread.new{start_hcmt}

# step 5, start observers
puts Time.now.to_s + ": Starting the observers..."
startObserver
# step 6, collect vmkstats
puts Time.now.to_s + ": Collecting vmkstats data..."
Thread.new{collectVmkstats}

# step 7, wait the benchmark job to join
tnode.each{|t|t.join}
# setp 8, stop observer and collect results.
puts Time.now.to_s + ": KAFKA tasks are done.."
puts Time.now.to_s + ": Stop the observers..."
stopObserver
puts Time.now.to_s + ": Processing observer stats files..."
processStatsfile
puts Time.now.to_s + ": Collecting support bundle info..."
collectSupportBundle
puts Time.now.to_s + ": Gathering KAFKA results..."
gather_hcmt_result
