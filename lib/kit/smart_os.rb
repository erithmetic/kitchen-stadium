require 'net/ssh'

module Kit
  class SmartOS
    def self.delete_instance(instance_id)
      Net::SSH.start('houston', 'root') do |ssh|
        puts ssh.exec! "vmadm destroy #{instance_id}"
      end
    end

    attr_accessor :site, :type, :host, :instance_id

    def initialize(site, type, host)
      self.site = site
      self.type = type
      self.host = host
    end

    def create_instance
      instance_id = nil
      report 'Creating instance...' do
        config['nics'].first['ip'] = host['ip']

        Net::SSH.start('houston', 'root') do |ssh|
          puts ssh.exec! "imgadm import #{IMAGE}"
          puts "vmadm create <<-EOF\n#{config.to_json}\nEOF"
          data = ssh.exec! "vmadm create <<-EOF\n#{config.to_json}\nEOF"
          puts data
          instance_id = data.scan(/VM (.*)/).flatten.last
          puts ssh.exec! "cp /root/.ssh/authorized_keys /zones/#{instance_id}/root/root/.ssh/"
        end
      end
      self.instance_id = instance_id

      fail 'Creation failed' if instance_id.nil?

      report "Writing node configuration..." do
        node_path = "nodes/#{host['ip']}.json"
        node = JSON.parse(File.read(node_path))
        node['run_list'] = %w{role[linux] role[development]}
        node['run_list'] << "recipe[app::#{type}_#{host['platform']}]"
        File.open(node_path, 'w') { |f| f.puts node.to_json }
      end

      puts "Created host #{instance_id}@#{host['ip']} with image #{IMAGE}"

      print "Waiting for host to boot"
      found = false
      while !found
        print '.'
        found = true if `ping -c 1 #{host['ip']}` !~ /0 packets received/
        sleep 1
      end
      puts 'ready!'
    end

    def nic_config
      {
        'nics' => [
          {
            'nic_tag' => 'admin',
            'model'   => 'virtio',
            'ip'      => host['ip'],
            'netmask' => '255.255.255.0',
            'gateway' => '192.168.1.254',
            'primary' => 1
          }
        ]
      }
    end

    class SmartMachine < SmartOS
      IMAGE = 'f669428c-a939-11e2-a485-b790efc0f0c1'

      ZONES = {
        dev: {
          'brand' => 'joyent',
          'alias' => 'app',
          'image_uuid' => IMAGE,
          'ram' => 1024
        },

        importer: {
          'brand' => 'joyent',
          'alias' => 'app-importer',
          'image_uuid' => IMAGE,
          'ram' => 1024
        }
      }

      def self.create_instance(site, type, host)
        smartos = new site, type, host
        smartos.create_instance
      end

      def config
        @config ||= ZONES[type].merge(nic_config)
      end
    end

    class Ubuntu
      IMAGE = 'da144ada-a558-11e2-8762-538b60994628'

      ZONES = {
        dev: {
          'brand' => 'kvm',
          'alias' => 'app',
          'ram' => 1024,
          'vcpus' => 2,
          'resolvers' => [
            '192.168.1.254'
          ],
          'disks' => [
            {
              'image_uuid' => IMAGE,
              'boot' => true,
              'model' => 'virtio',
              'size' => 12000
            }
          ]
        },
        importer: {
          'brand' => 'kvm',
          'alias' => 'app-importer',
          #'ram' => 2024,
          'vcpus' => 2,
          'resolvers' => [
            '192.168.1.254'
          ],
          'disks' => [
            {
              'image_uuid' => IMAGE,
              'boot' => true,
              'model' => 'virtio',
              'size' => 8000
            }
          ]
        }
      }

      def self.create_instance(site, type, host)
        ubuntu = new site, type, host
        ubuntu.create_instance
      end

      def config
        @config ||= ZONES[type].merge({
          "customer_metadata" => {
            "root_authorized_keys" => File.read("#{ENV['HOME']}/.ssh/id_rsa.pub")
          }
        }).merge(nic_config)
      end
    end
  end
end