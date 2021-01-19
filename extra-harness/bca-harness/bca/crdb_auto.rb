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
@workload_paras = ARGV[0]
@workload_paras = @workload_paras.split(",")

# ARGV[1] output folder path, please use the absolute path.
@outputfolder = ARGV[1]


@workload_folder_33 = "/opt/bca/workload-automation"
@workload_folder_34 = "/opt/bca/workload-automation-34"

@work_path = "#{@workload_folder_33}/cockroach/"
@auto_path = "#{@work_path}ansible/"
@terraform_path = "#{@work_path}terraform/"


# ARGV[4] "--run-only" , no VM cloning process needed with this switch.
runonly = false
if ARGV[2] == "--run-only"
	runonly = true
end

# Get the cluster names need to be monitored by the observer.
@observer_clusters = []
$datastore_names.each do |datastore_name|
    @observer_clusters << _get_vsan_cluster_from_datastore(datastore_name)
end

if not File.file?("#{@outputfolder}/crdb.log")
    `> #{@outputfolder}/crdb.log`
    File.write("#{@outputfolder}/crdb.log", "Start Time, Observer PIDs \n", mode: "a")
end

arr_node =[]
@credential = "#{$vc_username}:#{$vc_password}"
@vc = "#{$vc_ip}"
@dc = "#{$dc_name}"
#use the first datastore by default.
@datastore = "#{$datastore_names[0]}"
@prefix = "CRDB-VM-"
@host_password = "#{$host_password}"
@cluster = "#{$cluster_name}"
@vms_map = {}
@hosts_list = []
@dc_path = "/#{@vc}/#{@dc}"
@cl_path = "/#{@vc}/#{@dc}/computers/#{@cluster}"
@pids = []
@start_time = 0


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
    File.write("#{@outputfolder}/crdb.log", "#{time.to_s}, #{@pids}\n", mode: "a")
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

def inject_crdb(workload_type, init_inserts, run_duration, concurency)
    `ansible-playbook -i "#{@auto_path}"inventory.yml -i "#{@auto_path}"settings.yml "#{@auto_path}"bench-ycsb.yml --extra-vars \"workload_type=#{workload_type} init_inserts=#{init_inserts} run_duration=#{run_duration} concurency=#{concurency} perform_init=true perform_run=false\"`
end 

def start_crdb_bench(workload_type, init_inserts, run_duration, concurency, workload_folder)
    work_path = "#{workload_folder}/cockroach/"
    auto_path = "#{work_path}ansible/"

    p Time.now.to_s + ": Cleaning previous results..."
    `rm -r -f #{workload_folder}/cockroach/ansible/results/*`
    `ansible-playbook -i "#{auto_path}"inventory.yml -i "#{auto_path}"settings.yml "#{auto_path}"bench-ycsb.yml --extra-vars \"workload_type=#{workload_type} init_inserts=#{init_inserts} run_duration=#{run_duration} concurency=#{concurency} perform_init=false perform_run=true\"`
end 

def gather_crdb_result(workload_folder)
    wf=workload_folder.split('/')[-1]
    `mkdir -p #{@outputfolder}/crdb_results/#{wf}`
    `cp -r #{workload_folder}/cockroach/ansible/results/* #{@outputfolder}/crdb_results/#{wf}/`
end

def rebuild_env
    current_dir = Dir.pwd
    Dir.chdir("#{@terraform_path}")
    `terraform init`
    `terraform destroy -auto-approve`
    text = File.read("#{@terraform_path}terraform.tfvars.tmp")
    text = text.gsub("-datacenter-", "#{$dc_name}")
    text = text.gsub("-cluster-", "#{$cluster_name}")
    text = text.gsub("-datastore-", "#{@datastore}")
    File.open("#{@terraform_path}terraform.tfvars", "w") {|file| file.puts text }
    `terraform apply -auto-approve`
    `ansible -i "#{@auto_path}"settings.yml -i "#{@auto_path}"inventory.yml -m ping all`
    `ansible-playbook -i "#{@auto_path}"settings.yml  -i "#{@auto_path}"inventory.yml "#{@auto_path}"deploy.yml`
     Dir.chdir("#{current_dir}")
end

# step 1: cloning the VMs from the template and deploy CRDB
if not runonly
    p Time.now.to_s + ": Rebuilding the environment..."
    rebuild_env
    exit(255)
    # step 2: injecting data to the db, do this only once.
    p Time.now.to_s +  ": Injecting data to crdb..."
    inject_crdb(@workload_paras[0], @workload_paras[1], @workload_paras[2], @workload_paras[3])
end

# step 3, drop cache
p Time.now.to_s + ": Droping the cache..."
dropCache
# step 4 , start crdb jobs for all the VMs.
p Time.now.to_s +  ": Starting CRDB benchmark..."

tnode = []
tnode << Thread.new{start_crdb_bench(@workload_paras[0], @workload_paras[1], @workload_paras[2], @workload_paras[3], @workload_folder_33)}
tnode << Thread.new{start_crdb_bench(@workload_paras[0], @workload_paras[1], @workload_paras[2], @workload_paras[3], @workload_folder_34)}

# step 5, start observers
p Time.now.to_s + ": Starting the observers..."
startObserver
# step 6, collect vmkstats
p Time.now.to_s + ": Collecting vmkstats data..."
Thread.new{collectVmkstats}

# step 7, wait the benchmark job to join
tnode.each{|t|t.join}

# setp 8, stop observer and collect results.
p Time.now.to_s + ": CRDB tasks are done.."
p Time.now.to_s + ": Stop the observers..."
stopObserver
p Time.now.to_s + ": Processing observer stats files..."
processStatsfile
p Time.now.to_s + ": Collecting support bundle info..."
collectSupportBundle
p Time.now.to_s + ": Gathering CRDB results..."
gather_crdb_result(@workload_folder_33)
gather_crdb_result(@workload_folder_34)
