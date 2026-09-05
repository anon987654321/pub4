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
#   ruby OPENBSD/bin/domain_watch.rb --update   # rewrite the snapshot (OpenBSD/Linux)
#   ruby OPENBSD/bin/domain_watch.rb --json
#
# --update shells to /usr/bin/timeout. macOS has no that binary; refresh the
# snapshot on vm23.
#
# whois is rate-limited and several registries refuse queries from unknown
# clients. Anything we cannot determine is reported "unknown" and never counted
# as healthy — a monitor that reports green on a failed lookup is worse than none.

require "date"
require "json"
require "open3"
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
      "de" => "whois.denic.de", "fr" => "whois.nic.fr", "be" => "whois.dns.be",
      "us" => "whois.nic.us", "org" => "whois.pir.org",
    }.freeze

    AVAILABLE = /No match|NOT FOUND|not found|No entries found|is free|Status:\s*free|
                 is available|No Data Found|Object does not exist|not registered/xi
    REGISTERED = /Registrar:|Registrant|Registered on|Creation Date|Created:|
                  Name Server|nserver|Domain nameservers|holder/xi

    module_function

    def zones
      File.read(NSD_CONF).scan(/^\s*name:\s*"?([^"\s]+)"?/).flatten.uniq.sort
    end

    def whois_query(domain)
      server = SERVERS[domain.split(".").last]
      argv = ["whois"]
      argv += ["-h", server] if server
      argv << domain
      # Unqualified `timeout` is a cron PATH bug this tree has already shipped
      # (the snapshot was right and nothing looked at it). The interpolated
      # string was also a shell, so a zone name from nsd.conf would be parsed.
      # /usr/bin/timeout is the OpenBSD binary OPERATOR.sh already calls.
      out, = Open3.capture2e("/usr/bin/timeout", "15", *argv)
      return { "state" => "unknown", "note" => "lookup failed" } if out.to_s.strip.empty?

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
          # Nominet keeps saying "registered" for months after a .uk lapses and
          # puts the truth here instead: "Renewal required." Four of ours said
          # that on 2026-08-12, having expired in June, and the state field alone
          # reported all four as healthy.
          "status" => out[/Registration status:\s*\n?\s*(\S[^\n]*)/i, 1]&.strip,
          "registrar" => out[/Registrar:\s*\n?\s*(\S[^\n]*)/i, 1]&.strip,
        }.compact
      else
        { "state" => "unknown", "note" => out.lines.first.to_s.strip[0, 60] }
      end
    end

  # whois first, RDAP for the registries that will not answer it.
  #
  # Identity Digital (.legal, .attorney, .healthcare) and SWITCH (.ch, .li)
  # return an empty body to a plain whois, which the referral guard above then
  # correctly files as unknown rather than guessing. Thirty-eight of the fifty-
  # seven zones sat at unknown for that reason, so the snapshot could not answer
  # the only question it exists to answer.
  #
  # RDAP is what those registries serve instead, and it is only safe once you
  # know the registry actually runs it: a 404 means "no such domain" from a
  # registry that has RDAP, and "no service here" from one that does not, and
  # reading the second as available is the same mistake the guard above exists
  # to prevent. IANA publishes which TLDs have RDAP and where, so the bootstrap
  # is fetched first and a TLD missing from it is never called available.
  def query(domain)
    result = whois_query(domain)
    return result unless result["state"] == "unknown"

    rdap_query(domain) || result
  end

  BOOTSTRAP = "https://data.iana.org/rdap/dns.json"

  def rdap_base(tld)
    @rdap_bases ||= begin
      out, = Open3.capture2e("/usr/bin/timeout", "20", "curl", "-sS", BOOTSTRAP)
      parsed = JSON.parse(out.to_s)
      parsed.fetch("services", []).each_with_object({}) do |(tlds, urls), map|
        tlds.each { |t| map[t] = urls.first }
      end
    rescue StandardError
      {}
    end
    @rdap_bases[tld]
  end

  def rdap_query(domain)
    base = rdap_base(domain.split(".").last)
    return nil unless base

    url = "#{base.chomp("/")}/domain/#{domain}"
    out, = Open3.capture2e("/usr/bin/timeout", "20", "curl", "-sSL", "-w", "\n%{http_code}", url)
    lines = out.to_s.lines
    code = lines.last.to_s.strip
    return { "state" => "available" } if code == "404"
    return nil unless code == "200"

    body = JSON.parse(lines[0..-2].join) rescue nil
    return nil unless body

    event = ->(name) { body["events"]&.find { |e| e["eventAction"] == name }&.dig("eventDate") }
    {
      "state" => "registered",
      "created" => event.call("registration"),
      "expires" => event.call("expiration"),
      "registrar" => body["entities"]
                       &.find { |e| Array(e["roles"]).include?("registrar") }
                       &.dig("vcardArray", 1)&.find { |f| f[0] == "fn" }&.last,
    }.compact
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

    # An expiry date is not a warning until something reads it.
    #
    # The snapshot has carried "expires" since it was written, and nothing ever
    # compared it to today — compare() only noticed a domain going from
    # registered to available, which is the state it reaches after it is too late
    # to renew. On 2026-08-12 the committed file said cardff.uk and edinbrgh.uk
    # expired the following day, denvr.us the same day, and four .uk domains had
    # expired in June. All seven were sitting in the repo, in git, unread. The
    # same shape as bsdports.org expiring with a day's notice five days earlier
    # (c6bb41135), and the same shape as the cron PATH: the data was right and
    # nothing looked at it.
    EXPIRY_WARN_DAYS = 45

    # `13-Aug-2026` from Nominet, `2026-08-13T11:20:09Z` from the .us/.com
    # registries, and nothing at all from Norid — .no whois publishes no expiry,
    # so brgen.no and the three other .no cities cannot be watched this way and
    # are not silently counted as fine.
    def days_until(value)
      return nil if value.to_s.empty?

      date = begin
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
      date && (date - Date.today).to_i
    end

    def expiring(current, within: EXPIRY_WARN_DAYS)
      current.filter_map do |domain, row|
        next unless row["state"] == "registered"

        renewal_flagged = row["status"].to_s.match?(/renewal required|suspended|grace|redemption/i)
        days = days_until(row["expires"])
        next unless renewal_flagged || (days && days <= within)

        [domain, days, row["status"]]
      end.sort_by { |_, days, _| days || -9_999 }
    end

    def unwatchable(current)
      current.select { |_, row| row["state"] == "registered" && row["expires"].to_s.empty? }.keys
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

  expiring = Deploy::DomainWatch.expiring(current)
  if expiring.any?
    puts "\nEXPIRING or LAPSED (#{expiring.size}):"
    expiring.each do |domain, days, status|
      when_ = if status.to_s.match?(/renewal required|suspended|grace|redemption/i)
                status.to_s.sub(/\.\z/, "")
              elsif days.negative?
                "expired #{-days} day(s) ago"
              else
                "#{days} day(s) left"
              end
      puts "  #{domain.ljust(18)} #{when_}"
    end
    puts "  Renew at the registrar. Nothing in this repo can do it."
  end

  unwatchable = Deploy::DomainWatch.unwatchable(current)
  if unwatchable.any?
    # Named rather than skipped: these are registered and their expiry is simply
    # not knowable from whois, so a clean run above does not cover them.
    puts "\nno expiry published, not watched (#{unwatchable.size}):\n  #{unwatchable.join(', ')}"
  end

  if diff[:lost].any?
    puts "\nLOST since last snapshot: #{diff[:lost].join(', ')}"
  end
  if diff[:changed].any?
    puts "\nCHANGED HANDS:"
    diff[:changed].each { |line| puts "  #{line}" }
  end

  exit(diff[:lost].empty? && diff[:changed].empty? && expiring.empty? ? 0 : 1)
end
