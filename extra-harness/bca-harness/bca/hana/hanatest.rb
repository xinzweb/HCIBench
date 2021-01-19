#!/bin/env ruby

cases = ["4K Block, Log Volume 5GB, Overwrite","16K Block, Log Volume 16GB, Overwrite", "1M Block, Log Volume 16GB, Overwrite","1MB Block, Log Volume 16GB, Read","16KB Block, Data Volume 16GB", "16KB Block, Data Volume 16GB, Overwrite","64KB Block, Data Volume 16GB","64KB Block, Data Volume 16GB, Overwrite","64KB Block, Data Volume 16GB, Read","1MB Block, Data Volume 16GB", "1MB Block, Data Volume 16GB, Overwrite", "1MB Block, Data Volume 16GB, Read", "16MB Block, Data Volume 16GB","16MB Block, Data Volume 16GB, Overwrite", "16MB Block, Data Volume 16GB, Read", "64MB Block, Data Volume 16GB", "64MB Block, Data Volume 16GB, Overwrite","64MB Block, Data Volume 16GB, Read"] 


cases.sort.each do |testcase|
  puts testcase
  casename = testcase.gsub(" ","_").gsub(",","-")
  `mkdir -p /opt/output/results/hana/local_sep/#{casename}`
  `ruby /opt/bca/hana/hana_auto.rb "#{testcase}" /opt/output/results/hana/local_sep/#{casename} --run-only`
end


  
