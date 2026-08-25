#!/usr/bin/env ruby
# frozen_string_literal: true

# frozen_string_literal: true

path = ARGV[0] || "/etc/relayd.conf"
body = File.read(path)
lines = body.each_line.filter_map do |line|
  if line =~ /^\s*tls keypair "([^"]+)"/
    domain = Regexp.last_match(1)
    cert = "/etc/ssl/#{domain}.crt"
    fullchain = "/etc/ssl/#{domain}.fullchain.pem"
    next unless File.exist?(cert) || File.exist?(fullchain)
  end
  line
end
text = lines.join
File.write(path, text)
puts "relayd_prune_keypairs: #{path}"
