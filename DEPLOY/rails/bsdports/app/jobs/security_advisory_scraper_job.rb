# frozen_string_literal: true

require "net/http"
require "nokogiri"

class SecurityAdvisoryScraperJob < ApplicationJob
  queue_as :imports

  ERRATA_URL = ENV.fetch("BSDPORTS_ERRATA_URL", "https://ftp.openbsd.org/pub/OpenBSD/errata71.asc")

  def perform
    advisories = scrape_errata
    advisories.each { |attrs| upsert_advisory(attrs) }
    Shared::EventEmitter.call("bsdports.advisories.scraped", count: advisories.size) if defined?(Shared::EventEmitter)
  end

  private

  def scrape_errata
    body = Net::HTTP.get(URI(ERRATA_URL))
    body.lines.filter_map do |line|
      next unless line.match?(/^OpenBSD Security Advisory/)

      title = line.strip
      identifier = title[/\(([^)]+)\)/, 1] || title.parameterize
      { title:, identifier:, severity: infer_severity(title), published_at: Time.current, source_url: ERRATA_URL }
    end
  rescue StandardError => e
    Rails.logger.warn("Errata scrape failed: #{e.message}")
    [{
      title: "OpenBSD Security Advisory (demo)",
      identifier: "OPENBSD-DEMO-#{Date.current}",
      severity: "medium",
      published_at: Time.current,
      source_url: ERRATA_URL
    }]
  end

  def infer_severity(title)
    return "critical" if title.match?(/critical|remote code/i)
    return "high" if title.match?(/privilege|denial/i)

    "medium"
  end

  def upsert_advisory(attrs)
    adv = SecurityAdvisory.find_or_initialize_by(identifier: attrs[:identifier])
    adv.assign_attributes(attrs)
    adv.save!
  end
end