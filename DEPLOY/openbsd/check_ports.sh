#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if command -v ruby34 >/dev/null 2>&1; then
  exec ruby34 - "$ROOT" <<'RUBY'
root = ARGV.fetch(0)
paths = [
  "DEPLOY/openbsd/openbsd.sh",
  "DEPLOY/openbsd/etc/httpd.conf",
  "DEPLOY/openbsd/etc/relayd.conf",
  "DEPLOY/openbsd/etc/rc.conf.local",
  "DEPLOY/openbsd/etc/ssh/sshd_config",
]

pattern = /\b(?:port|PORT)\b\s*[:=]?\s*(?<port>\d{2,5})/
ports = Hash.new { |h, k| h[k] = [] }

paths.each do |rel|
  path = File.join(root, rel)
  next unless File.file?(path)
  File.readlines(path, chomp: true).each_with_index do |line, idx|
    line.scan(pattern) do
      port = Regexp.last_match[:port].to_i
      next if [22, 53, 80, 443].include?(port)
      ports[port] << "#{rel}:#{idx + 1}"
    end
  end
end

collisions = ports.select { |_port, locs| locs.size > 1 }
if collisions.any?
  collisions.each do |port, locs|
    warn "port collision #{port}: #{locs.join(', ')}"
  end
  exit 1
end

puts "port check ok"
RUBY
elif command -v rbenv >/dev/null 2>&1; then
  exec rbenv exec ruby - "$ROOT" <<'RUBY'
root = ARGV.fetch(0)
paths = [
  "DEPLOY/openbsd/openbsd.sh",
  "DEPLOY/openbsd/etc/httpd.conf",
  "DEPLOY/openbsd/etc/relayd.conf",
  "DEPLOY/openbsd/etc/rc.conf.local",
  "DEPLOY/openbsd/etc/ssh/sshd_config",
]

pattern = /\b(?:port|PORT)\b\s*[:=]?\s*(?<port>\d{2,5})/
ports = Hash.new { |h, k| h[k] = [] }

paths.each do |rel|
  path = File.join(root, rel)
  next unless File.file?(path)
  File.readlines(path, chomp: true).each_with_index do |line, idx|
    line.scan(pattern) do
      port = Regexp.last_match[:port].to_i
      next if [22, 53, 80, 443].include?(port)
      ports[port] << "#{rel}:#{idx + 1}"
    end
  end
end

collisions = ports.select { |_port, locs| locs.size > 1 }
if collisions.any?
  collisions.each do |port, locs|
    warn "port collision #{port}: #{locs.join(', ')}"
  end
  exit 1
end

puts "port check ok"
RUBY
else
  exec ruby - "$ROOT" <<'RUBY'
root = ARGV.fetch(0)
paths = [
  "DEPLOY/openbsd/openbsd.sh",
  "DEPLOY/openbsd/etc/httpd.conf",
  "DEPLOY/openbsd/etc/relayd.conf",
  "DEPLOY/openbsd/etc/rc.conf.local",
  "DEPLOY/openbsd/etc/ssh/sshd_config",
]

pattern = /\b(?:port|PORT)\b\s*[:=]?\s*(?<port>\d{2,5})/
ports = Hash.new { |h, k| h[k] = [] }

paths.each do |rel|
  path = File.join(root, rel)
  next unless File.file?(path)
  File.readlines(path, chomp: true).each_with_index do |line, idx|
    line.scan(pattern) do
      port = Regexp.last_match[:port].to_i
      next if [22, 53, 80, 443].include?(port)
      ports[port] << "#{rel}:#{idx + 1}"
    end
  end
end

collisions = ports.select { |_port, locs| locs.size > 1 }
if collisions.any?
  collisions.each do |port, locs|
    warn "port collision #{port}: #{locs.join(', ')}"
  end
  exit 1
end

puts "port check ok"
RUBY
fi
