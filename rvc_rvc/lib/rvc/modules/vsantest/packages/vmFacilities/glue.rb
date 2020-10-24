#!/usr/bin/ruby
require 'ipaddr'
require 'nokogiri'
require 'shellwords'

hash={}
doc = Nokogiri::XML(File.open("/root/tmp/ovfEnv.xml"))

doc.xpath('//xmlns:Property').map do |pp|
  hash[pp.attributes["key"].value]=pp.attributes["value"].value
end

if hash["Public_Network_Type"]=="Static"
  ip=hash["Public_Network_IP"]
  netsize=IPAddr.new(hash["Public_Network_Netmask"]).to_i.to_s(2).count("1")
  gw=hash["Public_Network_Gateway"]
  dns=hash["DNS"]
  `sed -i "s/yes/no/g" /etc/systemd/network/eth0.network`
  `sed -i "s/ipv4/no/g" /etc/systemd/network/eth0.network`
  `echo "Address=#{ip}/#{netsize}" >> /etc/systemd/network/eth0.network`
  `echo "Gateway=#{gw}" >> /etc/systemd/network/eth0.network`
  `echo "DNS=#{dns}" >> /etc/systemd/network/eth0.network`
  `systemctl restart systemd-networkd`
end

password=hash["System_Password"]
psd = Shellwords.escape("root:#{password}")
psd_escape = Shellwords.escape(password)

system(%{echo #{psd} | chpasswd})
tomcat = `/var/opt/apache-tomcat-8.5.4/bin/digest.sh -a md5 -h org.apache.catalina.realm.MessageDigestCredentialHandler #{psd_escape}`
tomcat_psd = tomcat.chomp.rpartition(":").last
`echo '<?xml version="1.0" encoding="UTF-8"?>' > /var/opt/apache-tomcat-8.5.4/conf/tomcat-users.xml`
`echo '<tomcat-users xmlns="http://tomcat.apache.org/xml" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd" version="1.0">' >> /var/opt/apache-tomcat-8.5.4/conf/tomcat-users.xml`
`echo '<role rolename="root"/>' >> /var/opt/apache-tomcat-8.5.4/conf/tomcat-users.xml`
`echo '<user username="root" password="#{tomcat_psd}" roles="root"/>' >> /var/opt/apache-tomcat-8.5.4/conf/tomcat-users.xml`
`echo '</tomcat-users>' >> /var/opt/apache-tomcat-8.5.4/conf/tomcat-users.xml`
`service tomcat stop; sleep 2; service tomcat start`
#`sh /root/tmp/DockerVolumeMover.sh -f`