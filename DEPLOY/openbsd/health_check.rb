#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

failures = []

def run(*cmd)
  out, status = Open3.capture2e(*cmd)
  [status.success?, out.strip]
end

services = %w[nsd httpd relayd smtpd master brgen_rails amber_rails bsdports_rails blognet_rails hjerterom_rails baibl]
services.each do |service|
  ok, out = run("/usr/sbin/rcctl", "check", service)
  next unless ok
  failures << "#{service}: #{out.empty? ? "check failed" : out}" unless out.include?("(ok)")
end

pfctl = File.executable?("/sbin/pfctl") ? "/sbin/pfctl" : "/usr/sbin/pfctl"
ok, out = run(pfctl, "-s", "rules")
failures << "pfctl: #{out.empty? ? "no rules output" : out}" unless ok && out.include?("block log all")

dns_cmd = %w[/usr/sbin/drill /usr/bin/drill].find { |c| File.executable?(c) }
if dns_cmd
  ok, out = run(dns_cmd, "@127.0.0.1", "brgen.no", "SOA")
  failures << "dns: #{out.empty? ? "no SOA response" : out}" unless ok && out.include?("brgen.no.")
else
  ok, out = run("/usr/bin/dig", "@127.0.0.1", "brgen.no", "SOA", "+short")
  failures << "dns: #{out.empty? ? "no SOA response" : out}" unless ok && !out.empty?
end

app_up_checks = {
  "master" => 53187,
  "brgen" => 38182,
  "amber" => 61352,
  "bsdports" => 47312,
  "baibl" => 10007,
  "blognet" => 10002,
  "hjerterom" => 38891
}
app_up_checks.each do |name, port|
  ok, out = run("/usr/local/bin/curl", "-fsS", "--max-time", "5", "http://127.0.0.1:#{port}/up")
  failures << "#{name} up: #{out.empty? ? "no response on :#{port}" : out}" unless ok
end

if File.file?("/etc/relayd.conf")
  relayd_conf = File.read("/etc/relayd.conf")
  unless relayd_conf.include?("forward to <master>") && relayd_conf.include?('check http "/up"')
    failures << "relayd: master backend missing http /up check"
  end
end

certs = %w[
  /etc/ssl/brgen.no.fullchain.pem
  /etc/ssl/amber.brgen.no.fullchain.pem
  /etc/ssl/bsdports.org.fullchain.pem
  /etc/ssl/baibl.brgen.no.crt
  /etc/ssl/blognet.brgen.no.crt
]
certs.each do |cert|
  failures << "cert missing: #{cert}" unless File.exist?(cert)
end

https_checks = {
  "ai.brgen.no" => "https://ai.brgen.no/up",
  "brgen.no" => "https://brgen.no/up",
  "amber.brgen.no" => "https://amber.brgen.no/up",
  "baibl.brgen.no" => "https://baibl.brgen.no/up",
  "blognet.brgen.no" => "https://blognet.brgen.no/up",
  "hjerterom.brgen.no" => "https://hjerterom.brgen.no/up",
  "bsdports.org" => "https://bsdports.org/up"
}
https_checks.each do |name, url|
  ok, out = run("/usr/local/bin/curl", "-fsS", "--max-time", "10", url)
  failures << "#{name} https: #{out.empty? ? "no response" : out}" unless ok
end

if failures.any?
  warn failures.join("\n")
  exit 1
end

puts "health check ok"
