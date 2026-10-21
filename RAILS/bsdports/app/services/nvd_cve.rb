# frozen_string_literal: true

require "time"
require "net/http"
require "json"
require "uri"

class NvdCve
  Result = Data.define(:status, :count, :error)

  BASE = "https://services.nvd.nist.gov/rest/json/cves/2.0"

  # Request pacing belongs to NvdCveCrossrefJob, which reserves slots in a
  # shared database row and reschedules work instead of sleeping a request or
  # worker thread. Keep this service focused on fetching and recording data.

  def self.crossref(port, limit: 5)
    new(port).crossref(limit:)
  end

  def initialize(port)
    @port = port
  end

  def crossref(limit: 5)
    advisories = fetch(limit).filter_map { |v| record(v["cve"] || {}) }
    Result.new(status: :succeeded, count: advisories.size, error: nil)
  rescue StandardError => e
    Rails.logger.warn("NVD CVE crossref failed for #{@port.name}: #{e.class}: #{e.message}")
    Result.new(status: :failed, count: 0, error: e.class.name)
  end

  private

    def fetch(limit)
      q = "openbsd #{@port.name}"
      uri = URI("#{BASE}?keywordSearch=#{URI.encode_www_form_component(q)}&resultsPerPage=#{limit}")

      headers = {}
      if (key = ENV["NVD_API_KEY"]).present?
        headers["apiKey"] = key
      end
      res = Shared::OutboundHttp.request(
        uri, headers:, max_body: Shared::OutboundHttp::MAX_BODY,
        open_timeout: 5, read_timeout: 10
      )
      raise IOError, "NVD returned HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body)
      vulnerabilities = data["vulnerabilities"]
      raise JSON::ParserError, "NVD response has no vulnerabilities array" unless vulnerabilities.is_a?(Array)

      vulnerabilities
    end

    # The advisory for one CVE, saved, or nil when it has no id or will not save.
    def record(cve)
      id = cve["id"]
      return if id.blank?

      desc = cve.dig("descriptions", 0, "value").to_s[0, 500]
      title = desc[0, 200].presence || id
      metrics = cve.dig("metrics", "cvssMetricV31", 0, "cvssData") ||
                cve.dig("metrics", "cvssMetricV2", 0, "cvssData") || {}
      score = metrics["baseScore"]
      pub = cve["published"]

      # The unique identifier index is the race-safe identity boundary. Two
      # ports can discover the same CVE at once; create_or_find_by! returns the
      # single canonical advisory instead of losing the second port on a race.
      adv = SecurityAdvisory.create_or_find_by!(identifier: id) do |record|
        record.title = title
        record.description = desc.presence
        record.published_at = pub.present? ? Time.parse(pub) : Time.current
        record.cvss_score = score if score
        record.source_url = "https://nvd.nist.gov/vuln/detail/#{id}"
        record.severity = severity(score) if score
      end

      adv.title = title if adv.title.blank?
      adv.description = desc if adv.description.blank? && desc.present?
      adv.published_at ||= pub.present? ? Time.parse(pub) : Time.current
      adv.cvss_score = score if score
      adv.source_url ||= "https://nvd.nist.gov/vuln/detail/#{id}"
      adv.severity = severity(score) if score
      adv.save! if adv.changed?

      # One NVD identifier can affect many ports. The join's unique index and
      # create_or_find_by! make repeated and concurrent cross-references safe.
      SecurityAdvisoryPort.create_or_find_by!(security_advisory: adv, port: @port)
      adv
    end

    def severity(score)
      case
      when score >= 9 then :critical
      when score >= 7 then :high
      when score >= 4 then :medium
      else :low
      end
    end
end
