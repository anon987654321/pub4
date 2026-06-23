#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

failures = []

def run(*cmd)
  out, status = Open3.capture2e(*cmd)
  [status.success?, out.strip]
end

def privileged(*cmd)
  return cmd if Process.uid.zero?
  return ["doas", "-n", *cmd] if File.executable?("/usr/bin/doas") || File.executable?("/bin/doas")
  cmd
end

core_services = %w[nsd httpd relayd smtpd master brgen_rails]
optional_services = %w[amber_rails bsdports_rails blognet_rails hjerterom_rails baibl]
(core_services + optional_services).each do |service|
  ok, out = run(*privileged("/usr/sbin/rcctl", "check", service))
  next unless ok
  running = out.include?("(ok)")
  if optional_services.include?(service)
    next unless running
  end
  failures << "#{service}: #{out.empty? ? "check failed" : out}" unless running
end

pfctl = File.executable?("/sbin/pfctl") ? "/sbin/pfctl" : "/usr/sbin/pfctl"
ok, out = run(*privileged(pfctl, "-s", "rules"))
pf_ok = ok && out.include?("block") && out.include?("log all")
failures << "pfctl: #{out.empty? ? "no rules output" : out}" unless pf_ok

dns_ok = false
if File.executable?("/usr/bin/dig")
  dns_ok, dns_out = run("/usr/bin/dig", "@127.0.0.1", "brgen.no", "SOA", "+short", "+time=2", "+tries=1")
  dns_ok &&= !dns_out.empty? && dns_out.include?("brgen.no")
elsif (dns_cmd = %w[/usr/sbin/drill /usr/bin/drill].find { |c| File.executable?(c) })
  dns_ok, dns_out = run(dns_cmd, "@127.0.0.1", "brgen.no", "SOA")
  dns_ok &&= dns_out.include?("brgen.no.")
end
unless dns_ok
  nsd_ok, nsd_out = run(*privileged("/usr/sbin/rcctl", "check", "nsd"))
  failures << "dns: no local SOA (nsd #{nsd_out.strip})" unless nsd_ok && nsd_out.include?("(ok)")
end

core_up = { "master" => 53187, "brgen" => 38182 }
optional_up = { "amber" => 61352, "bsdports" => 47312, "baibl" => 10007, "blognet" => 10002, "hjerterom" => 38891 }
core_up.merge(optional_up).each do |name, port|
  svc = name == "master" ? "master" : "#{name}_rails"
  svc = "baibl" if name == "baibl"
  check_ok, check_out = run(*privileged("/usr/sbin/rcctl", "check", svc))
  next if optional_up.key?(name) && !(check_ok && check_out.include?("(ok)"))

  ok, out = run("/usr/local/bin/curl", "-fsS", "--max-time", "20", "http://127.0.0.1:#{port}/up")
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
  /etc/ssl/hjerterom.brgen.no.crt
]
certs.each do |cert|
  failures << "cert missing: #{cert}" unless File.exist?(cert)
end

core_https = {
  "ai.brgen.no" => "https://ai.brgen.no/up",
  "brgen.no" => "https://brgen.no/up"
}
optional_https = {
  "amber.brgen.no" => "https://amber.brgen.no/up",
  "baibl.brgen.no" => "https://baibl.brgen.no/up",
  "blognet.brgen.no" => "https://blognet.brgen.no/up",
  "hjerterom.brgen.no" => "https://hjerterom.brgen.no/up",
  "bsdports.org" => "https://bsdports.org/up"
}
core_https.merge(optional_https).each do |name, url|
  if optional_https.key?(name)
    backend = name.split(".").first
    backend = "bsdports" if name == "bsdports.org"
    svc = backend == "baibl" ? "baibl" : "#{backend}_rails"
    check_ok, check_out = run(*privileged("/usr/sbin/rcctl", "check", svc))
    next unless check_ok && check_out.include?("(ok)")
  end
  ok, out = run("/usr/local/bin/curl", "-fsS", "--max-time", "25", url)
  failures << "#{name} https: #{out.empty? ? "no response" : out}" unless ok
end

if failures.any?
  warn failures.join("\n")
  exit 1
end

puts "health check ok"
