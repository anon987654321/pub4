# frozen_string_literal: true

require "set"
require "yaml"

module Brgen
  # Explicit production host allow-list for Rails config.hosts.
  # Sources: domains.yml (Bergen verticals), DomainRegistry city domains,
  # and DEPLOY/openbsd/openbsd.sh ALL_DOMAINS subapp surfaces.
  module ProductionHosts
    SUBAPPS = %w[playlist dating tv takeaway maps].freeze
    BRGEN_ONLY_SUBAPPS = %w[ai].freeze
    VERTICAL_ALIASES = {
      "playlist" => %w[playlist spilleliste]
    }.freeze

    DOMAINS_YML = File.expand_path("../../domains.yml", __dir__)

    module_function

    def allowed
      hosts = Set.new

      hosts << "brgen.no"
      hosts << "www.brgen.no"
      vertical_hosts_from_domains_yml.each { |host| hosts << host }
      bergen_vertical_hosts.each { |host| hosts << host }

      DomainRegistry::ENTRIES.each do |entry|
        hosts << entry.domain
        hosts << "www.#{entry.domain}"
        hosts << "#{entry.marketplace_subdomain}.#{entry.domain}"

        SUBAPPS.each do |subapp|
          VERTICAL_ALIASES.fetch(subapp, [subapp]).each do |label|
            hosts << "#{label}.#{entry.domain}"
          end
        end

        next unless entry.domain == "brgen.no"

        BRGEN_ONLY_SUBAPPS.each do |subapp|
          hosts << "#{subapp}.#{entry.domain}"
        end
      end

      hosts.to_a.sort
    end

    def vertical_hosts_from_domains_yml
      return [] unless File.file?(DOMAINS_YML)

      data = YAML.safe_load_file(DOMAINS_YML, permitted_classes: [Symbol])
      domains = data.dig("primary", "domains") || {}
      domains.values
    rescue StandardError
      []
    end

    def bergen_vertical_hosts
      %w[
        markedsplass.brgen.no
        playlist.brgen.no
        spilleliste.brgen.no
        dating.brgen.no
        tv.brgen.no
        takeaway.brgen.no
        maps.brgen.no
        ai.brgen.no
      ]
    end
  end
end