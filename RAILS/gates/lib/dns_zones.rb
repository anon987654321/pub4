# frozen_string_literal: true

require "resolv"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../../OPENBSD/bin/render_dns"

module Deploy
  # The DNS the repo describes has to be the DNS the box serves.
  #
  # Before 2026-08-12 there were four hand-written descriptions of the same set
  # of names and no two agreed: ALL_DOMAINS had 53 domains, /var/nsd/zones/master
  # had 61 zone files, nsd.conf declared 54, and acme-client.conf carried a fifth,
  # older subdomain list. Nothing compared them, so the drift was only visible by
  # reading all four — and the cost of it was that oshlo.no, a live certificated
  # city, had no www record, no SPF and no DMARC while brgen.no had all three.
  #
  # Now bin/render_dns.rb writes all of it from ALL_DOMAINS plus data/dns.yml.
  # This gate is what makes the generator load-bearing rather than optional: it
  # fails if the committed output is not what the generator produces, which is
  # the moment someone hand-edits a zone file.
  #
  # The live half is a DNS query, not a file read. /var/nsd/zones/master is 640
  # _nsd:_nsd, so a gate running as dev cannot read a zone on the box either —
  # but anyone can ask the nameserver. Signature freshness needs the files and
  # lives in OPENBSD/health_check.rb, which runs as root on vm23.
  class DnsZonesGate
    ROOT = File.expand_path("../../..", __dir__)
    REGISTRY = File.join(ROOT, "RAILS", "brgen", "lib", "brgen", "domain_registry.rb")
    NAMESERVER = "46.23.89.226"

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      generated_output_matches
      every_domain_has_a_zone
      nameserver_answers
      @result
    end

    private

    def generated_output_matches
      _written, stale = RenderDns.render_zones(check: true)
      %w[nsd.conf acme-client.conf].zip([RenderDns::NSD_CONF, RenderDns::ACME_CONF]).each do |label, path|
        body = label == "nsd.conf" ? RenderDns.nsd_conf_body : RenderDns.acme_conf_body
        stale << label unless File.exist?(path) && File.read(path, encoding: "UTF-8") == body
      end

      if stale.empty?
        @result.checked!(RenderDns.zones.size + 2)
      else
        @result.fail("dns_zones: #{stale.size} generated file(s) differ from what data/dns.yml renders " \
                     "(#{stale.sort.first(5).join(', ')}) — run `ruby OPENBSD/bin/render_dns.rb`")
      end
    end

    # Every domain the installer deploys must have a zone file and a zone block.
    # Seven zone files were served by nobody for months because nsd.conf and the
    # directory were maintained separately.
    def every_domain_has_a_zone
      declared = RenderDns.zones.keys
      conf = File.read(RenderDns::NSD_CONF, encoding: "UTF-8").scan(/name:\s+"([^"]+)"/).flatten

      missing_block = declared - conf
      orphan_block = conf - declared
      @result.fail("dns_zones: nsd.conf has no zone block for #{missing_block.sort.join(', ')}") if missing_block.any?
      @result.fail("dns_zones: nsd.conf declares #{orphan_block.sort.join(', ')} with no zone file") if orphan_block.any?
      @result.checked!(declared.size)
    end

    # A city the registry calls live must actually be answered for by our
    # nameserver, apex and every vertical. Skipped rather than failed when UDP 53
    # is unavailable — several networks, including the machine this is usually
    # run from, block outbound port 53.
    def nameserver_answers
      live = live_domains
      return @result.inconclusive!("dns_zones: LIVE_DOMAINS not parseable") if live.empty?

      resolver = Resolv::DNS.new(nameserver: [NAMESERVER], search: [], ndots: 1)
      resolver.timeouts = 3

      begin
        resolver.getaddress("brgen.no")
      rescue Resolv::ResolvError, Resolv::ResolvTimeout, SystemCallError => e
        return @result.skipped_live("dns_zones: #{NAMESERVER} unreachable on UDP 53 (#{e.class}) — " \
                                    "live half not measured")
      end

      subdomains = RenderDns.city_zones
      live.each { |domain| check_domain(resolver, domain, Array(subdomains[domain])) }
    end

    def check_domain(resolver, domain, subdomains)
      names = [domain, "www.#{domain}"] + subdomains.map { |sub| "#{sub}.#{domain}" }
      by_verdict = names.group_by { |name| answer(resolver, name) }
      missing = Array(by_verdict[:missing])
      timed_out = Array(by_verdict[:timeout])

      if missing.any?
        @result.fail("dns_zones: #{domain} is in LIVE_DOMAINS and #{NAMESERVER} does not answer for " \
                     "#{missing.sort.join(', ')}")
      end
      if timed_out.any?
        @result.skipped_live("dns_zones: #{NAMESERVER} timed out for #{timed_out.sort.join(', ')} " \
                             "after #{RETRIES} attempts — not measured, not absent")
      end
      @result.checked!(names.size - timed_out.size)
    end

    # Answers over UDP, retried, because a timeout is not an absent record.
    #
    # This gate hard-failed on the first Resolv::ResolvTimeout, and one such
    # failure is what running it for the first time produced: "frankfrt.de is in
    # LIVE_DOMAINS and 46.23.89.226 does not answer for maps.frankfrt.de", while
    # `dig @46.23.89.226 maps.frankfrt.de` answered immediately and three
    # consecutive re-runs of the gate passed. A false block, from one dropped UDP
    # packet in the ~500 sequential queries this makes.
    #
    # arXiv 2607.07405 is the reason that matters rather than being a re-run
    # someone shrugs at: it audits a four-gate suite and finds one gate blocking
    # at 100% precision and another at 5%, and a gate whose blocks are mostly its
    # own noise is one people learn to skip. This gate was already invisible —
    # registered in gates.yml and invoked by nothing — so its first impression on
    # anyone wiring it up would have been a block that was not true.
    #
    # NXDOMAIN keeps failing. That is the gate's actual job, and it is a
    # different exception class from the one that was costing precision.
    RETRIES = 3

    def answer(resolver, name)
      attempts = 0
      begin
        attempts += 1
        resolver.getaddress(name)
        :ok
      rescue Resolv::ResolvTimeout
        retry if attempts < RETRIES
        :timeout
      rescue Resolv::ResolvError
        :missing
      end
    end

    def live_domains
      match = File.read(REGISTRY, encoding: "UTF-8").match(/LIVE_DOMAINS\s*=\s*%w\[([^\]]+)\]/)
      return [] unless match

      match[1].split(/\s+/).reject(&:empty?)
    end
  end
end
