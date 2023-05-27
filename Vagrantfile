cluster_size = ENV['CLUSTER_SIZE'] || 3
cluster_type = ENV['CLUSTER_TYPE'] || 'swarm'
cluster_ip_range = ENV['CLUSTER_IP_RANGE'] || "172.16.8.100"
cluster_vm_name = ENV['CLUSTER_VM_NAME'] || "cluster"

def increment_ip_address(ip_address = ENV['CLUSTER_IP_RANGE'] || "172.16.8.100", increment = 0)
  # Split the IP address into chunks
  chunks = ip_address.split('.')
  
  # Ensure there are four octets in the IP address
  if chunks.length != 4
    return "Invalid IP address."
  end

  # Increment the last chunk
  last_chunk = chunks[-1].to_i + increment.to_i

  # Validate the last chunk value
  if last_chunk < 0 || last_chunk > 255
    return "The new IP address is invalid."
  end

  # Update the last chunk
  chunks[-1] = last_chunk.to_s

  # Reassemble the IP address
  new_ip_address = chunks.join('.')

  new_ip_address
end

Vagrant.configure(2) do |config|

  (1..cluster_size).each do |i|
    config.vm.define "#{cluster_vm_name}-#{i}" do |s|
      s.ssh.forward_agent = true
      s.vm.box = "ubuntu/focal64"
      s.vm.hostname = "#{cluster_vm_name}-#{i}"

      s.vm.network "private_network", ip: increment_ip_address(cluster_ip_range, i), netmask: "255.255.255.0", auto_config: true, virtualbox__intnet: "#{cluster_vm_name}a-net"
      # s.vm.network "public_network", use_dhcp_assigned_default_route: true, bridge: [
      #   "wlp0s20f3", # Dell XPS 15 9510,
      #   "enp0s31f6", # Home LAN
      #   "wlp3s0"     # Home Wifi
      # ]
      
      s.vm.provider "virtualbox" do |v|
        v.name = "#{cluster_vm_name}-#{i}"
        v.cpus = 2
        v.memory = 3072
        v.gui = false
      end

      if i == 1
        s.vm.provision :shell do |c|
          c.inline = "bash /vagrant/scripts/registry.sh $1"
          c.args = [increment_ip_address(cluster_ip_range, 1)]
        end
      elsif i == 2
        s.vm.provision :shell do |c|
          c.inline = "bash /vagrant/bootstrap/#{cluster_type}/master.sh -r $1 -a $2"
          c.args = [increment_ip_address(cluster_ip_range, 1), increment_ip_address(cluster_ip_range, i)]
        end
      else
        s.vm.provision :shell do |c|
          c.inline = "bash /vagrant/bootstrap/#{cluster_type}/master.sh -r $1 -a $2 $3"
          c.args = ["172.16.8.101", "172.16.8.102", "172.16.8.10#{i}"]
        end
      end
    end
  end

end