#!/usr/bin/env ruby
# frozen_string_literal: true

# One-pass OpenBSD production health check.
# Run on the VPS: ruby /home/dev/pub4/DEPLOY/health_check.rb
#
# Verifies rcctl services, relayd /up probes, PF rules, TLS certs, and DNS.

require "json"
require "open3"
require "yaml"

ROOT = File.expand_path(__dir__)
APPS_YML = File.join(ROOT, "rails", "apps.yml")
BRGEN_IP = ENV.fetch("BRGEN_IP", "46.23.89.226")

SERVICES = %w[nsd httpd relayd smtpd master brgen amber bsdports baibl blognet hjerterom litestream].freeze

def run(cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  { cmd: cmd.join(" "), stdout: stdout.strip, stderr: stderr.strip, ok: status.success? }
end

def record(results, name, ok, detail)
  results << { name: name, ok: ok, detail: detail }
end

def check_service(results, svc)
  out = run(%w[/usr/sbin/rcctl check svc])
  ok = out[:ok] && out[:stdout].include?("(ok)")
  record(results, "service:#{svc}", ok, out[:stdout].presence || out[:stderr])
end

def check_pf(results)
  out = run(%w[/sbin/pfctl -s rules])
  ok = out[:ok] && !out[:stdout].empty?
  record(results, "pf:rules", ok, ok ? "#{out[:stdout].lines.count} rules loaded" : out[:stderr])
end

def check_cert(results, domain)
  cert = "/etc/ssl/#{domain}.fullchain.pem"
  ok = File.file?(cert)
  detail =
    if ok
      expire = run(%W[openssl x509 -enddate -noout -in #{cert}])
      expire[:stdout].presence || "present"
    else
      "missing #{cert}"
    end
  record(results, "cert:#{domain}", ok, detail)
end

def check_dns(results, domain)
  out = run(%W[/usr/bin/dig @#{BRGEN_IP} #{domain} A +short])
  answer = out[:stdout].lines.map(&:strip).reject(&:empty?).first
  ok = answer == BRGEN_IP
  record(results, "dns:#{domain}", ok, answer || out[:stderr])
end

def check_up(results, name, port)
  out = run(%W[curl -s -o /dev/null -w %{http_code} --max-time 10 http://127.0.0.1:#{port}/up])
  ok = out[:ok] && out[:stdout] == "200"
  record(results, "up:#{name}", ok, "HTTP #{out[:stdout].presence || 'error'}")
end

apps =
  if YAML.respond_to?(:safe_load_file)
    YAML.safe_load_file(APPS_YML).fetch("apps")
  else
    YAML.safe_load(File.read(APPS_YML), permitted_classes: [], aliases: true).fetch("apps")
  end

results = []

SERVICES.each { |svc| check_service(results, svc) }
check_pf(results)

apps.each_value do |meta|
  check_cert(results, meta.fetch("domain"))
  check_dns(results, meta.fetch("domain"))
  check_up(results, meta.fetch("domain"), meta.fetch("port"))
end

check_cert(results, "ai.brgen.no")
check_dns(results, "brgen.no")

summary = {
  checked_at: Time.now.utc.iso8601,
  brgen_ip: BRGEN_IP,
  passed: results.count { |r| r[:ok] },
  failed: results.count { |r| !r[:ok] },
  results: results
}

puts JSON.pretty_generate(summary)
exit(summary[:failed].zero? ? 0 : 1)