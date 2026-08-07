#!/usr/bin/env ruby
# frozen_string_literal: true

# Which of our domains are still ours, and which have gone.
#
# amstrdam.nl was registered to us and served Amsterdam. It lapsed, dropped, and
# was re-registered by someone else on 2026-05-18 — GoDaddy, Cloudflare
# nameservers, 301 to an unrelated site. Nobody noticed for 81 days, because
# nothing was watching. lndon.uk dropped the same way. Four .uk domains sit in
# Nominet's grace window right now.
#
# nsd.conf lists the zones we serve. This asks each registry whether we still
# hold the name, and diffs the answer against a committed snapshot so a domain
# changing hands shows up as a reviewable diff instead of an outage.
#
#   ruby OPENBSD/bin/domain_watch.rb            # report against the snapshot
#   ruby OPENBSD/bin/domain_watch.rb --update   # rewrite the snapshot
#   ruby OPENBSD/bin/domain_watch.rb --json
#
# whois is rate-limited and several registries refuse queries from unknown
# clients. Anything we cannot determine is reported "unknown" and never counted
# as healthy — a monitor that reports green on a failed lookup is worse than none.

require "json"
require "yaml"

module Deploy
  module DomainWatch
    ROOT = File.expand_path("../..", __dir__)
    NSD_CONF = File.join(ROOT, "OPENBSD/var/nsd/etc/nsd.conf")
    SNAPSHOT = File.join(ROOT, "OPENBSD/data/domain_inventory.yml")

    # Registries whose referral the local whois does not follow correctly.
    SERVERS = {
      "uk" => "whois.nic.uk", "it" => "whois.nic.it", "pl" => "whois.dns.pl",
      "pt" => "whois.dns.pt", "nl" => "whois.domain-registry.nl",
      "no" => "whois.norid.no", "com" => "whois.verisign-grs.com",
      "net" => "whois.verisign-grs.com", "se" => "whois.iis.se",
      "dk" => "whois.dk-hostmaster.dk", "fi" => "whois.fi", "is" => "whois.isnic.is",
      "de" => "whois.denic.de", "fr" => "whois.nic.fr", "be" => "whois.dns.be"
    }.freeze

    AVAILABLE = /No match|NOT FOUND|not found|No entries found|is free|Status:\s*free|
                 is available|No Data Found|Object does not exist|not registered/xi
    REGISTERED = /Registrar:|Registrant|Registered on|Creation Date|Created:|
                  Name Server|nserver|Domain nameservers|holder/xi

    module_function

    def zones
      File.read(NSD_CONF).scan(/^\s*name:\s*"?([^"\s]+)"?/).flatten.uniq.sort
    end

    def query(domain)
      server = SERVERS[domain.split(".").last]
      cmd = server ? "whois -h #{server} #{domain}" : "whois #{domain}"
      out = `timeout 15 #{cmd} 2>&1`
      return { "state" => "unknown", "note" => "lookup failed" } if out.strip.empty?

      # A referral answer describes the TLD, not the name. Without this, .us and
      # .org queries returned the registry's own record and every domain looked
      # registered since 1985-02-15 — the date the .us TLD was created, reported
      # as if it were the domain's. Require the response to name the domain
      # itself before believing anything it says about registration.
      unless out.downcase.include?(domain.downcase) || out.match?(AVAILABLE)
        return { "state" => "unknown", "note" => "registry referral, not a domain record" }
      end

      if out.match?(AVAILABLE)
        { "state" => "available" }
      elsif out.match?(REGISTERED)
        {
          "state" => "registered",
          # Ordered most-specific first. A bare "Created:" also appears in the
          # registry's own trailing record, which is how bsdports.org reported
          # 1985-01-01 — the .org TLD's birthday, not the domain's.
          "created" => out[/Creation Date[.\s]*:\s*(\S+)/i, 1] ||
                       out[/Registered on[.\s]*:\s*(\S+)/i, 1] ||
                       out[/Created[.\s]*:\s*(\S+)/i, 1],
          "expires" => out[/(?:Expiry date|Registry Expiry Date|Expires on)[.\s]*:\s*(\S+)/i, 1],
          "registrar" => out[/Registrar:\s*\n?\s*(\S[^\n]*)/i, 1]&.strip
        }.compact
      else
        { "state" => "unknown", "note" => out.lines.first.to_s.strip[0, 60] }
      end
    end

    # Subdomains of a zone we already hold are not separately registrable.
    def registrable?(domain)
      domain.count(".") == 1
    end

    def snapshot
      File.exist?(SNAPSHOT) ? YAML.safe_load_file(SNAPSHOT) : {}
    end

    def scan
      zones.select { |z| registrable?(z) }.to_h { |z| [z, query(z)] }
    end

    def compare(current, previous)
      lost = []
      changed = []
      current.each do |domain, now|
        was = previous[domain]
        next unless was

        lost << domain if was["state"] == "registered" && now["state"] == "available"
        if was["state"] == "registered" && now["state"] == "registered" &&
           was["created"] && now["created"] && was["created"] != now["created"]
          changed << "#{domain}: created #{was['created']} -> #{now['created']} (re-registered by someone else)"
        end
      end
      { lost:, changed: }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  current = Deploy::DomainWatch.scan
  previous = Deploy::DomainWatch.snapshot
  diff = Deploy::DomainWatch.compare(current, previous)

  if ARGV.include?("--update")
    File.write(Deploy::DomainWatch::SNAPSHOT,
               "# Written by OPENBSD/bin/domain_watch.rb --update. Committed so a domain\n" \
               "# changing hands is a reviewable diff rather than a surprise outage.\n" +
               YAML.dump(current))
    puts "snapshot written: #{current.size} domains"
    exit 0
  end

  if ARGV.include?("--json")
    puts JSON.pretty_generate(current: current, **diff)
    exit(diff[:lost].empty? && diff[:changed].empty? ? 0 : 1)
  end

  by_state = current.group_by { |_, row| row["state"] }.transform_values(&:size)
  puts "domains checked: #{current.size} — #{by_state.map { |k, v| "#{k} #{v}" }.join(', ')}"

  available = current.select { |_, r| r["state"] == "available" }.keys
  puts "\nnot registered (#{available.size}):\n  #{available.join(', ')}" if available.any?

  unknown = current.select { |_, r| r["state"] == "unknown" }.keys
  puts "\nlookup inconclusive (#{unknown.size}):\n  #{unknown.join(', ')}" if unknown.any?

  if diff[:lost].any?
    puts "\nLOST since last snapshot: #{diff[:lost].join(', ')}"
  end
  if diff[:changed].any?
    puts "\nCHANGED HANDS:"
    diff[:changed].each { |line| puts "  #{line}" }
  end

  exit(diff[:lost].empty? && diff[:changed].empty? ? 0 : 1)
end
