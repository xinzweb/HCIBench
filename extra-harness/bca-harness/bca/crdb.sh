for workload in "A" #"B" "C" "F" 
do
  for con in 64 #32 64 128 16
  do
  mkdir -p /opt/output/results/crdb_sep_remote/$workload/$con
  ruby crdb_auto.rb "$workload,2000,3600,$con" /opt/output/results/crdb_sep_remote/$workload/$con --run-only
  sleep 300
  done
done



