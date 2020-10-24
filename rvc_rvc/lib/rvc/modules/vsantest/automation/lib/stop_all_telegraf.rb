#!/usr/bin/ruby
require_relative "rvc-util.rb"
require "logger"
#Get the container id by name

logfilepath = "#{$log_path}telegraf.log"
log = Logger.new(logfilepath)
log.level = Logger::INFO

begin
    `docker stop telegraf_vsan`
    telegraf_running = `docker ps -a | grep telegraf_vsan | grep Up | wc -l`
    if telegraf_running == "0"
      log.info "Container telegraf_vsan stopped"
    else
      _retry = 0
      while _retry < 5
        if `docker ps -a | grep telegraf_vsan | grep Up | wc -l` == "1"
          log.info "Container telegraf_vsan still running, retry in 3 seconds"
          sleep(3)
          _retry += 1
        else
          log.info "Container telegraf_vsan stopped"
          break
        end
      end
    end
rescue Exception => e
    log.error "Exception happened: #{e.message}"
end