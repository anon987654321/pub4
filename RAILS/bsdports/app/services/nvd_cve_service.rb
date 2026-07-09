# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class NvdCveService
  BASE = "https://services.nvd.nist.gov/rest/json/cves/2.0"

  def self.crossref(port, limit: 5)
    new(port).crossref(limit: limit)
  end

  def initialize(port)
    @port = port
  end

  def crossref(limit: 5)
    q = "openbsd #{@port.name}"
    uri = URI("#{BASE}?keywordSearch=#{URI.encode_www_form_component(q)}&resultsPerPage=#{limit}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10

    req = Net::HTTP::Get.new(uri)
    if (key = ENV["NVD_API_KEY"]).present?
      req["apiKey"] = key
    end

    res = http.request(req)
    return [] unless res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(res.body) rescue {}
    vulns = data.dig("vulnerabilities") || []

    created = []
    vulns.each do |v|
      cve = v.dig("cve") || {}
      id = cve["id"]
      next unless id

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

      if score
        adv.severity = case
        when score >= 9 then :critical
        when score >= 7 then :high
        when score >= 4 then :medium
        else :low
        end
      end

      created << adv if adv.save
    end
    created
  rescue StandardError => e
    Rails.logger.warn("NVD CVE crossref failed for #{@port.name}: #{e.message}")
    []
  end
end
