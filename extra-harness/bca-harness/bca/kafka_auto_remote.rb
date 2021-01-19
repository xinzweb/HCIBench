#!/bin/env ruby
require 'yaml'
require 'time'
require 'net/ssh'
require 'net/scp'
require 'optparse'
require "/opt/automation/lib/util.rb"
require "/opt/automation/lib/rvc-util.rb"

# example 1: build the environment, inject the data, and run the experiment.
# command : ruby auto_crdb.rb "A,200,120,10" /opt/bca/test --run-only

# example 2: run the experiment only without build the env and injecting the data.
# command example 2: ruby auto_crdb.rb "A,200,120,10" /opt/bca/test 

# ARGV[0] workload type(A,B,C,D,E), init_inserts, duration, concurrency,
# example" A, 250000, 3600, 60"
#@workload_paras = ARGV[0]
#@workload_paras = @workload_paras.split(",")
@test_choser = ARGV[0]
# ARGV[1] output folder path, please use the absolute path.
@outputfolder = ARGV[1]

@BRK_NUM = 8
@CNT_NUM = ARGV[2] || 8
@DATA_NUM = 4

@workload_folder_33 = "/opt/bca/automation-kafka"
@workload_folder_34 = "/opt/bca/automation-kafka-34"

# ARGV[4] "--run-only" , no VM cloning process needed with this switch.
runonly = false
if ARGV[3] == "--run-only"
	runonly = true
end

# Get the cluster names need to be monitored by the observer.
@observer_clusters = []
$datastore_names.each do |datastore_name|
    @observer_clusters << _get_vsan_cluster_from_datastore(datastore_name)
end

if not File.file?("#{@outputfolder}/kafka.log")
    `> #{@outputfolder}/kafka.log`
    File.write("#{@outputfolder}/kafka.log", "Start Time, Observer PIDs \n", mode: "a")
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

def start_kafka_bench(workload_folder)
    current_dir = Dir.pwd
    auto_path = File.join(workload_folder, "ansible/")
    p Time.now.to_s + ": Cleaning previous results..."
    `cd #{auto_path}; rm -r -f results/*`
    `cd #{auto_path}; bash #{@test_choser}.sh`
end

def gather_kafka_result(workload_folder)
    `mkdir -p #{@outputfolder}/kafka_results/#{workload_folder}`
    `cp -r #{workload_folder}/ansible/results #{@outputfolder}/kafka_results/#{workload_folder}`
end

def rebuild_env_terraform(workload_folder)
    cl_name = "Cluster-34"
    ds_name = "vsanDatastore-33"
    if workload_folder.include? "34"
      cl_name = "Cluster-33"
      ds_name = "vsanDatastore-34"
    end 

    # Save PWD
    # current_dir = Dir.pwd
    auto_path = File.join(workload_folder, "ansible/")
    terraform_path = File.join(workload_folder, "terraform/")

    # CL File.join is a much safer way to join paths in ruby.
    puts "Ansible path for #{workload_folder}: #{auto_path}"
    puts "Terraform path for #{workload_folder}: #{terraform_path}"

    # Terraform
    puts `cd #{terraform_path}; terraform init; terraform destroy -auto-approve`
    text = File.read("#{terraform_path}terraform.tfvars.tmp")
    text = text.gsub("-datacenter-", "#{$dc_name}")
    text = text.gsub("-cluster-", "#{cl_name}")
    text = text.gsub("-datastore-", "#{ds_name}")
    text = text.gsub("-brk-num-",@BRK_NUM.to_s)
    text = text.gsub("-cnt-num-",@CNT_NUM.to_s)
    text = text.gsub("-data-num-",@DATA_NUM.to_s)
    File.open("#{terraform_path}terraform.tfvars", "w") {|file| file.puts text }
    puts `cd #{terraform_path}; terraform apply -auto-approve`

    # Ansible
    puts `cd #{auto_path}; ansible -i settings.yml -i inventory.yml -m ping all; ansible-galaxy install -r ansible-requirements.yml; ansible-playbook -i settings.yml -i inventory.yml preflight-playbook.yml; ansible-playbook -i settings.yml -i inventory.yml all.yml; ansible-playbook -i settings.yml -i inventory.yml tools-provisioning.yml`
    # Restore PWD
    # Dir.chdir("#{current_dir}")
end

# step 1: cloning the VMs from the template and deploy CRDB
if not runonly
    p Time.now.to_s + ": Rebuilding the environment..."
    runnode = []
    runnode << Thread.new{rebuild_env_terraform(@workload_folder_33)}
    runnode << Thread.new{rebuild_env_terraform(@workload_folder_34)}
    runnode.each{|t|t.join}
end
# step 3, drop cache
p Time.now.to_s + ": Droping the cache..."
dropCache
# step 4 , start kafka jobs for all the VMs.
p Time.now.to_s +  ": Starting KAFKA benchmark..."

tnode = []
tnode << Thread.new{start_kafka_bench(@workload_folder_33)}
tnode << Thread.new{start_kafka_bench(@workload_folder_34)}

# step 5, start observers
p Time.now.to_s + ": Starting the observers..."
startObserver
# step 6, collect vmkstats
p Time.now.to_s + ": Collecting vmkstats data..."
Thread.new{collectVmkstats}

# step 7, wait the benchmark job to join
tnode.each{|t|t.join}

# setp 8, stop observer and collect results.
p Time.now.to_s + ": KAFKA tasks are done.."
p Time.now.to_s + ": Stop the observers..."
stopObserver
p Time.now.to_s + ": Processing observer stats files..."
processStatsfile
p Time.now.to_s + ": Collecting support bundle info..."
collectSupportBundle
p Time.now.to_s + ": Gathering KAFKA results..."
gather_kafka_result(@workload_folder_33)
gather_kafka_result(@workload_folder_34)

