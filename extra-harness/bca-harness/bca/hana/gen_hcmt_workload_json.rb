#!/bin/env ruby
require 'json'


#### generate small json from the template ###

workload = ARGV[0]
remote_hana_vm_list = ARGV[1]
@json_temp = "/opt/bca/hana/test.json.template"
@json_new = "/opt/bca/hana/#{workload.gsub(" ","_").gsub(",","-")}.json"
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