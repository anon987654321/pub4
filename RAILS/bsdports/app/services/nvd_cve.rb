# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class NvdCve
  BASE = "https://services.nvd.nist.gov/rest/json/cves/2.0"

  # Request pacing belongs to NvdCveCrossrefJob, which reserves slots in a
  # shared database row and reschedules work instead of sleeping a request or
  # worker thread. Keep this service focused on fetching and recording data.

  def initialize(port)
    @port = port
  end

  def crossref(limit: 5)
    fetch(limit).filter_map { |v| record(v["cve"] || {}) }
  rescue StandardError => e
    Rails.logger.warn("NVD CVE crossref failed for #{@port.name}: #{e.message}")
    []
  end

  private

    def fetch(limit)
      q = "openbsd #{@port.name}"
      uri = URI("#{BASE}?keywordSearch=#{URI.encode_www_form_component(q)}&resultsPerPage=#{limit}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      req = Net::HTTP::Get.new(uri)
      if (key = ENV["NVD_API_KEY"]).present?
        req["apiKey"] = key
      end

      res = http.request(req)
      return [] unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body)
      data.dig("vulnerabilities") || []
    rescue JSON::ParserError
      []
    end

    # The advisory for one CVE, saved, or nil when it has no id or will not save.
    def record(cve)
      id = cve["id"]
      return unless id

      desc = cve.dig("descriptions", 0, "value").to_s[0, 500]
      metrics = cve.dig("metrics", "cvssMetricV31", 0, "cvssData") ||
                cve.dig("metrics", "cvssMetricV2", 0, "cvssData") || {}
      score = metrics["baseScore"]
      pub = cve["published"]

      adv = SecurityAdvisory.find_or_initialize_by(identifier: id)
      adv.port ||= @port
      adv.title = desc[0, 200] if adv.title.blank?
      adv.description = desc if adv.description.blank?
      adv.published_at ||= pub ? Time.parse(pub) : Time.current
      adv.cvss_score = score if score
      adv.source_url ||= "https://nvd.nist.gov/vuln/detail/#{id}"
      adv.severity = severity(score) if score
      return unless adv.save

      # One NVD identifier can affect many ports. The join's unique index and
      # find_or_create_by! make repeated cross-references idempotent.
      SecurityAdvisoryPort.find_or_create_by!(security_advisory: adv, port: @port)
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
