#!/usr/bin/env ruby
# Mirror /etc/* into pub4/MASTER/__openbsd/etc/ with secret redaction.
# Run on VPS: doas ruby ~/pub4/MASTER/__openbsd/sync.rb

require "fileutils"

MIRROR = File.expand_path("..", __FILE__)

SOURCES = [
  "/etc/rc.d/master", "/etc/rc.d/brgen", "/etc/rc.d/brgen_tv", "/etc/rc.d/brgen_rails",
  "/etc/rc.d/amber", "/etc/rc.d/amber_rails", "/etc/rc.d/baibl",
  "/etc/rc.d/blognet", "/etc/rc.d/blognet_rails",
  "/etc/rc.d/bsdports", "/etc/rc.d/bsdports_rails",
  "/etc/rc.d/hjerterom", "/etc/rc.d/hjerterom_rails",
  "/etc/relayd.conf", "/etc/httpd.conf", "/etc/pf.conf",
  "/etc/acme-client.conf", "/var/nsd/etc/nsd.conf",
  "/etc/login.conf", "/etc/rc.conf.local",
  "/home/dev/.zshrc",
].freeze

SECRET_PATTERNS = [
  /(_API_KEY=)\S+/,
  /(_KEY=)sk-\S+/,
  /(SECRET_KEY_BASE=)[a-f0-9]{32,}/,
  /(_TOKEN=)\S+/,
  /(_PASSWORD=)\S+/,
  /(_SECRET=)\S+/,
].freeze

def redact(body)
  SECRET_PATTERNS.inject(body) { |acc, pat| acc.gsub(pat, '\1__REDACTED__') }
end

mirrored = []
skipped  = []
SOURCES.each do |path|
  unless File.exist?(path)
    skipped << path
    next
  end
  body = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
  redacted = redact(body)
  dest = File.join(MIRROR, path.sub(%r{^/}, ""))
  FileUtils.mkdir_p(File.dirname(dest))
  File.write(dest, redacted)
  mirrored << path
end

puts "mirrored #{mirrored.size}:"
mirrored.each { |p| puts "  #{p}" }
if skipped.any?
  puts "skipped (not present): #{skipped.size}"
  skipped.each { |p| puts "  #{p}" }
end
