require 'socket'
require 'ipaddress'

class ValidateSubnets

  def initialize
    @interfaces = Socket.getifaddrs
  end

  def ipv4_conflict?(target)
    response = Array.new

    # Find target interface
    target_interface = @interfaces.find {|x| x.addr&.ipv4? and x.netmask.ipv4? and x.name.casecmp(target) == 0}
    raise("Could not find target interface #{target_interface.name}") unless target_interface

    # Create target IPAddress object for comparisons
    target_net = IPAddress.parse(target_interface.addr.ip_address + '/' + target_interface.netmask.ip_address)

    # Check every interface
    @interfaces.each do |interface|

      # Check if interface is IPv4 and not the target
      if interface.addr&.ipv4? and interface.name.casecmp(target) != 0

        # Create interface network
        interface_net = IPAddress.parse "#{interface.addr.ip_address}#{"/#{interface.netmask.ip_address}" if interface.netmask&.ipv4?}"

        if target_net.include?(interface_net)
          response.push("Interface #{target_interface.name} (#{target_net.to_string}) contains the network on interface #{interface.name} (#{interface_net.to_string})")
        elsif interface_net.include?(target_net)
          response.push("Interface #{interface.name} (#{interface_net.to_string}) contains the network on interface #{target} (#{target_net.to_string})")
        end
      end
    end
    response.any? ? response : nil
  end

  def list_ipv4
    @interfaces.each do |x|
      if x.addr&.ipv4?
        net = IPAddress.parse "#{x.addr.ip_address}#{"/#{x.netmask.ip_address}" if x.netmask&.ipv4?}"
        puts "#{x.name}: #{net.to_string}"
      end
    end
  end

end