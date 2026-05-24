#!/usr/bin/env ruby
# frozen_string_literal: true
# Mirror live VPS config into snapshot/ with secret redaction.
# Run on VPS: doas ruby ~/pub4/DEPLOY/openbsd/snapshot/sync.rb

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

def dest_for(path)
  case path
  when %r{^/etc/rc\.d/(.+)}   then File.join(MIRROR, "etc", "rc.d", $1)
  when %r{^/etc/(.+)}         then File.join(MIRROR, "etc", $1)
  when %r{^/var/nsd/etc/(.+)} then File.join(MIRROR, "var", "nsd", "etc", $1)
  when %r{^/home/dev/(.+)}    then File.join(MIRROR, "etc", File.basename($1))
  else                              File.join(MIRROR, "etc", File.basename(path))
  end
end

mirrored = []
skipped  = []
SOURCES.each do |path|
  unless File.exist?(path)
    skipped << path
    next
  end
  body = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
  dest = dest_for(path)
  FileUtils.mkdir_p(File.dirname(dest))
  File.write(dest, redact(body))
  mirrored << path
end

puts "mirrored #{mirrored.size}:"
mirrored.each { |p| puts "  #{p}" }
if skipped.any?
  puts "skipped (not present): #{skipped.size}"
  skipped.each { |p| puts "  #{p}" }
end
