# HCIBench
I have this repo maintained is for user to upgrade their HCIBench instance without deploying another OVA.
To upgrade your HCIBench:
  1. You need to have HCIBench Controller VM running
  2. Your HCIBench Controller VM should have internet connectivity
  3. SSH into your HCIBench Controller VM and run 
  #################################################################################################
  tdnf install -y git && git clone https://github.com/cwei44/HCIBench.git && sh HCIBench/upgrade.sh
  #################################################################################################
  to upgrade your HCIBench to the latest build
  4. the logs, results and configuration files would be preserved after upgrading to the latest build.
