#!/usr/bin/env ruby
# frozen_string_literal: true
# Mirror live VPS config into OPENBSD/ with secret redaction.
# Run on VPS: doas ruby34 ~/pub4/OPENBSD/sync.rb

require "fileutils"

MIRROR = File.expand_path(__dir__)

FIXED_SOURCES = [
  "/etc/rc.d/master", "/etc/rc.d/brgen",
  "/etc/rc.d/amber",
  "/etc/rc.d/bsdports",
  "/etc/relayd.conf", "/etc/httpd.conf", "/etc/pf.conf",
  "/etc/acme-client.conf", "/var/nsd/etc/nsd.conf",
  "/etc/login.conf", "/etc/rc.conf.local",
  "/home/dev/.zshrc",
].freeze

# Zone data is deliberately NOT mirrored. We run our own authoritative nsd and
# carry a lot of domains: /var/nsd/zones/master holds 61 zones, and the signed
# artifacts (*.zone.signed, K*.key, K*.ds) are regenerated on every re-sign, so
# mirroring them would put a churning copy of the DNS into every git diff while
# the nameserver — not the repo — remains the source of truth. This script used
# to glob all four patterns; it had never been run, which is the only
# reason the repo is clean of them. nsd.conf stays in FIXED_SOURCES above: that
# is server configuration, not zone data.
#
# Decided 2026-08-02. If you are here to "fix" the missing zones, don't.
SOURCES = FIXED_SOURCES.uniq.freeze

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
  when %r{^/etc/rc\.d/(.+)} then File.join(MIRROR, "etc", "rc.d", $1)
  when %r{^/etc/(.+)} then File.join(MIRROR, "etc", $1)
  when %r{^/var/nsd/etc/(.+)} then File.join(MIRROR, "var", "nsd", "etc", $1)
  when %r{^/var/nsd/zones/(.+)} then File.join(MIRROR, "var", "nsd", "zones", $1)
  when %r{^/home/dev/(.+)} then File.join(MIRROR, "etc", File.basename($1))
  else File.join(MIRROR, "etc", File.basename(path))
  end
end

mirrored = []
skipped = []
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
