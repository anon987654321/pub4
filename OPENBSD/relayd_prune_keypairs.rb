#!/usr/bin/env ruby
# frozen_string_literal: true

# Drop `tls keypair` lines whose certificate is not on disk, because relayd
# refuses to start over one and takes every site down with it.
#
#   ruby34 OPENBSD/relayd_prune_keypairs.rb [PATH]           # report only (default)
#   ruby34 OPENBSD/relayd_prune_keypairs.rb --apply [PATH]   # rewrite PATH
#
# Report-only unless told otherwise: this rewrites /etc/relayd.conf, and a tool
# that edits the front door by default is one a curious run can break.
# OPERATOR.sh passes --apply, then `relayd -n` validates the result.

if ARGV.intersect?(%w[-h --help])
  puts "usage: relayd_prune_keypairs.rb [--apply] [PATH]   (default PATH /etc/relayd.conf; report-only without --apply)"
  exit 0
end

apply = ARGV.delete("--apply")
path = ARGV[0] || "/etc/relayd.conf"
body = File.read(path)
dropped = []
lines = body.each_line.filter_map do |line|
  if line =~ /^\s*tls keypair "([^"]+)"/
    domain = Regexp.last_match(1)
    cert = "/etc/ssl/#{domain}.crt"
    fullchain = "/etc/ssl/#{domain}.fullchain.pem"
    unless File.exist?(cert) || File.exist?(fullchain)
      dropped << domain
      next
    end
  end
  line
end

dropped.each { |domain| puts "relayd_prune_keypairs: no certificate for #{domain}" }
if apply
  File.write(path, lines.join) unless dropped.empty?
  puts "relayd_prune_keypairs: #{path} (#{dropped.size} keypair(s) removed)"
else
  puts "relayd_prune_keypairs: #{path} unchanged (#{dropped.size} keypair(s) would be removed; pass --apply)"
end
