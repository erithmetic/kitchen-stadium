require 'kit/amazon'

module Kit
  class ServerList < Array
    def self.all
      aws_servers = Amazon.aws.servers.inject({}) do |hsh, server|
        key = server.tags['Name']
        hsh[key] ||= []
        hsh[key] << server
        hsh
      end

      servers = new
      Kit.hosts.each do |site, types|
        types.each do |type, hosts|
          hosts.each do |color, data|
            server = Server.new site, type, color
            if subset = aws_servers.delete(server.instance_name)
              subset.each do |aws_server|
                s = server.dup
                s.update_info!(aws_server)
                servers << s
              end
            else
              servers << server
            end
          end
        end
      end

      remaining = aws_servers.map do |instance_name, subset|
        subset.each do |aws_server|
          server = Server.find_by_ip aws_server.public_ip_address
          server ||= Server.new '?', '?', '?'
          server.update_info!(aws_server)

          servers << server
        end
      end

      servers
    end

    def self.find_by_name(site, type, color)
      needle = Server.new site, type, color
      running.find_all { |s| s.instance_name == needle.instance_name }
    end

    def self.running
      all.running
    end

    def self.formatted(method_or_list, options = {})
      require 'terminal-table'
      items = []
      headers = []
      headers << 'Selection' if options[:numbered]
      headers += ['Site', 'Type', 'Color', 'Status', 'IP', 'ID', 'Uptime']
      items << headers

      list = if method_or_list.is_a?(Symbol)
               send(method_or_list)
             else
               method_or_list
             end

      number = 0
      items += list.map do |server|
        item = server.status_line
        item.unshift number if options[:numbered]
        number += 1
        item
      end

      table = Terminal::Table.new :rows => items
      puts table
    end

    def self.find_by_ip(ip)
      all.find_by_ip(ip)
    end

    def running
      find_all { |s| s.running? }
    end

    def find_by_ip(ip)
      find { |s| s.ip == ip }
    end
  end
end
