# frozen_string_literal: true

require "json"
require "pathname"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../../OPENBSD/lib/gate_result"

begin
  require_relative "../../../shared/lib/pub4/deploy_paths"
rescue LoadError
  # ok for minimal ruby env
end

module Deploy
  class DomainAlignmentGate
    ROOT = Pathname.new(File.expand_path("../../../..", __dir__))
    OPENBSD = ROOT.join("OPENBSD", "OPERATOR.sh")
    REGISTRY = ROOT.join("RAILS", "brgen", "lib", "brgen", "domain_registry.rb")
    DEPLOY_INVENTORY = ROOT.join("OPENBSD", "deploy_inventory.json")
    RELAYD = ROOT.join("OPENBSD", "etc", "relayd.conf")
    COMMON_SUBAPPS = %w[playlist dating tv takeaway maps messenger].freeze
    MASTER_ONLY_SUBAPPS = %w[ai].freeze

    def self.run
      new.run
    end

    def run
      result = GateResult.new
      openbsd = parse_openbsd_domains
      registry = parse_registry_entries
      routes = parse_registry_subdomains

      if defined?(Pub4::DeployPaths) && Pub4::DeployPaths.respond_to?(:validate_layout!)
        begin
          Pub4::DeployPaths.validate_layout!
        rescue StandardError => e
          result.fail("deploy layout: #{e.message}")
        end
      end

      missing_dns = registry.keys - openbsd.keys
      result.fail("domain set mismatch: missing DNS #{missing_dns.sort.join(', ')}") if missing_dns.any?

      registry.each do |domain, marketplace_subdomain|
        expected = expected_subdomains_for(domain, marketplace_subdomain)
        actual = openbsd.fetch(domain, [])
        missing = expected - actual
        extra = actual - expected
        result.fail("#{domain}: DNS missing #{missing.join(', ')}") if missing.any?
        result.fail("#{domain}: DNS extra #{extra.join(', ')}") if extra.any?
      end

      %w[tv dating takeaway maps messenger].each do |subapp|
        routes.fetch(subapp.to_sym).each do |label|
          next if COMMON_SUBAPPS.include?(label) || MASTER_ONLY_SUBAPPS.include?(label)

          result.fail("routes #{subapp} lists unknown label #{label}")
        end
      end

      routes.fetch(:playlist).each do |label|
        next if label == "playlist"

        result.fail("routes playlist lists unknown label #{label}")
      end

      master = parse_deploy_inventory
      relayd_keys = parse_relayd_keypairs

      if master[:apps] && !master[:apps].empty?
        # Derived from apps.yml, not restated. This table used to be a literal
        # of the same three domain/port pairs, which made the gate a fifth copy
        # of the fact it exists to protect: edit apps.yml and the gate keeps
        # asserting the old numbers, and passes. port_inventory checks the other
        # four mirrors against apps.yml but does not read gates/lib, so nothing
        # would have caught the drift.
        expected_apps = Inventory.new(root: ROOT.to_s).apps.to_h do |app|
          [app.name, { domain: app.domain, port: app.port }]
        end
        expected_apps.each do |name, exp|
          entry = master[:apps][name]
          unless entry
            result.fail("deploy_inventory.json missing #{name}")
            next
          end
          result.fail("deploy_inventory.json domain mismatch for #{name}: #{entry['domain']} != #{exp[:domain]}") if entry["domain"] != exp[:domain]
          result.fail("deploy_inventory.json port mismatch for #{name}: #{entry['port']} != #{exp[:port]}") if entry["port"].to_i != exp[:port]
        end
        m = master[:master] || {}
        if m["domain"] != "ai.brgen.no" || m["port"].to_i != 53187
          result.fail("deploy_inventory.json master_face mismatch: #{m['domain']}:#{m['port']}")
        end
      end

      # Derived, for the same reason the port table above it is. This was a literal
      # %w[brgen.no ai.brgen.no amber.brgen.no bsdports.org] -- the last hardcoded
      # fleet list inside the gate whose whole purpose is proving the fleet agrees.
      # A fourth app would have shipped with no keypair assertion and the gate would
      # have passed, which is exactly how relayd.conf drifted unnoticed for ports.
      live_apexes(master).each do |dom|
        result.fail("relayd.conf missing tls keypair for #{dom}") unless relayd_keys.include?(dom)
      end

      live_domains_check(result, registry.keys, relayd_keys)

      result
    end

    private

    # LIVE_DOMAINS must be exactly the city apexes relayd holds a keypair for.
    #
    # It is the list the layout iterates to draw the city network, so it decides
    # what a visitor can click. Both directions of drift are real and both have
    # happened:
    #
    #   too many  a domain in the list that relayd will not serve is a link to a
    #             TLS handshake failure, which a browser reports as an attack.
    #   too few   a domain relayd serves and the list omits is a city nobody can
    #             reach from the site. Five sat like that from whenever they were
    #             issued until 2026-08-12 — stvanger.no, trndheim.no, cardff.uk,
    #             edinbrgh.uk and frankfrt.de all had certificates, all resolved
    #             here, and none was linked or served.
    #
    # Source, not network. relayd.conf is tracked and is what gets installed, so
    # this holds off the deploy host and in CI — and a gate that needed DNS to run
    # would be the kind that passes having measured nothing.
    def live_domains_check(result, registry_domains, relayd_keys)
      declared = extract_constant(REGISTRY.read, "LIVE_DOMAINS")
      certified = registry_domains & relayd_keys

      unknown = declared - registry_domains
      result.fail("LIVE_DOMAINS names #{unknown.join(', ')}, absent from ENTRIES") if unknown.any?

      missing = certified - declared
      extra = declared - certified - unknown

      if missing.any?
        result.fail("LIVE_DOMAINS omits #{missing.sort.join(', ')} — relayd.conf has a tls keypair " \
                    "for each, so they serve and nothing links them")
      end
      if extra.any?
        result.fail("LIVE_DOMAINS names #{extra.sort.join(', ')} with no tls keypair in relayd.conf — " \
                    "the city network links a hostname that refuses TLS")
      end

      result.checked!(declared.size)
    end

    # Every domain that terminates TLS on vm23: the apps from apps.yml plus the
    # MASTER face, which is not a Rails app and so lives in deploy_inventory.json's
    # master_face rather than apps.yml.
    def live_apexes(master)
      apps = begin
        Inventory.new(root: ROOT.to_s).apps.map(&:domain)
      rescue StandardError
        []
      end
      face = master.dig(:master, "domain")
      (apps + [face]).compact.uniq
    end

    def parse_openbsd_domains
      text = OPENBSD.read
      block = text[/ALL_DOMAINS=\(\n(.*?)\n\)/m, 1]
      raise "ALL_DOMAINS block not found in #{OPENBSD}" unless block

      block.lines.filter_map do |line|
        line = line.strip
        next if line.empty?

        domain, subs = line.split(":", 2)
        subdomains = subs ? subs.split(",").map(&:strip) : []
        [domain, subdomains]
      end.to_h
    end

    def parse_registry_entries
      text = REGISTRY.read
      text.scan(/Entry\.new\("([^"]+)",\s*"[^"]+",\s*"[^"]+",\s*:[^,]+,\s*"[^"]+",\s*"([^"]+)"\)/).to_h
    end

    def parse_registry_subdomains
      text = REGISTRY.read
      {
        tv: extract_constant(text, "TV_SUBDOMAINS"),
        dating: extract_constant(text, "DATING_SUBDOMAINS"),
        playlist: extract_constant(text, "PLAYLIST_SUBDOMAINS"),
        takeaway: extract_constant(text, "TAKEAWAY_SUBDOMAINS"),
        maps: extract_constant(text, "MAPS_SUBDOMAINS"),
        messenger: extract_constant(text, "MESSENGER_SUBDOMAINS"),
      }
    end

    def extract_constant(text, name)
      match = text.match(/#{name}\s*=\s*%w\[([^\]]+)\]/)
      raise "missing #{name} in domain_registry.rb" unless match

      # reject(&:empty?), because a %w[] wrapped across lines starts with a
      # newline and split leaves an empty first element — which then compares
      # unequal against every real list and fails the gate on formatting.
      match[1].split(/\s+/).reject(&:empty?)
    end

    def expected_subdomains_for(domain, marketplace_subdomain)
      # The marketplace subdomain is the only translated one — it comes from the
      # registry row (markedsplass, marknadsplats, marktplatz, mercato, ...).
      # Everything else is the same word in every city.
      subs = [marketplace_subdomain, *COMMON_SUBAPPS]
      subs << "ai" if domain == "brgen.no"
      subs.uniq
    end

    def parse_deploy_inventory
      return {} unless DEPLOY_INVENTORY.exist?

      data = JSON.parse(DEPLOY_INVENTORY.read)
      apps = (data["apps"] || []).each_with_object({}) { |a, h| h[a["name"]] = a }
      master = data["master_face"] || {}
      { apps: apps, master: master }
    end

    def parse_relayd_keypairs
      return [] unless RELAYD.exist?

      RELAYD.read.scan(/tls keypair "([^"]+)"/).flatten
    end
  end
end
