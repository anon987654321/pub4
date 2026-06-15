#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

failures = []

def run(*cmd)
  out, status = Open3.capture2e(*cmd)
  [status.success?, out.strip]
end

services = %w[nsd httpd relayd smtpd master]
services.each do |service|
  ok, out = run("/usr/sbin/rcctl", "check", service)
  failures << "#{service}: #{out.empty? ? "check failed" : out}" unless ok && out.include?("(ok)")
end

pfctl = File.executable?("/sbin/pfctl") ? "/sbin/pfctl" : "/usr/sbin/pfctl"
ok, out = run(pfctl, "-s", "rules")
failures << "pfctl: #{out.empty? ? "no rules output" : out}" unless ok && out.include?("block log all")

ok, out = run("/usr/sbin/drill", "@127.0.0.1", "brgen.no", "SOA")
failures << "dns: #{out.empty? ? "no SOA response" : out}" unless ok && out.include?("brgen.no.")

ok, out = run("/usr/local/bin/curl", "-fsS", "http://127.0.0.1:53187/up")
failures << "master up: #{out.empty? ? "no response" : out}" unless ok

certs = %w[/etc/ssl/brgen.no.fullchain.pem /etc/ssl/amber.brgen.no.fullchain.pem /etc/ssl/bsdports.org.fullchain.pem]
certs.each do |cert|
  failures << "cert missing: #{cert}" unless File.exist?(cert)
end

if failures.any?
  warn failures.join("\n")
  exit 1
end

puts "health check ok"
