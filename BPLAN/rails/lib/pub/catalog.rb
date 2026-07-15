# frozen_string_literal: true

require "json"
require "pathname"
require "yaml"
require File.expand_path("../../../lib/bplan/constants", __dir__)

module Bplan
  class Catalog
    BPLAN_ROOT = Pathname.new(File.expand_path("../../..", __dir__)).freeze
    ASSET_PREFIX = "/content"
    PLAN_ORDER = Bplan::Constants::PLAN_ORDER
    BASE_URL = ENV.fetch("BPLAN_BASE_URL", "https://bplan.pub.healthcare").freeze

    class << self
      def funding
        @funding ||= YAML.load_file(BPLAN_ROOT.join("funding.yml"))
      end

      def manifest
        @manifest ||= YAML.load_file(BPLAN_ROOT.join("legats/manifest.yml"))
      end

      def applicant
        funding.fetch("applicant", {})
      end

      def convergence_version
        funding.dig("portfolio", "convergence_version") || 1
      end

      def plans
        PLAN_ORDER.filter_map do |slug|
          venture = funding.dig("ventures", slug)
          next unless venture

          {
            slug: slug,
            title: venture["title"],
            track: venture["track"],
            trl: venture["trl"],
            pitch: venture["wholesome_pitch"].to_s.strip,
            ask_legat_nok: venture["ask_legat_nok"].to_i,
            ask_in_nok: venture["ask_in_nok"].to_i,
            project_total_nok: venture["project_total_nok"].to_i,
          }
        end
      end

      def plans_json
        plans.map(&:dup)
      end

      def plan(slug)
        plans.find { |p| p[:slug] == slug.to_s }
      end

      def legats
        manifest.fetch("applications", [])
      end

      def legats_sendable
        legats.select { |entry| sendable?(entry) }
      end

      def legats_filtered(track: nil, include_low_priority: false)
        list = legats
        list = list.reject { |entry| entry["low_priority"] } unless include_low_priority
        list = list.select { |entry| entry["track"] == track.to_s } if track.present?
        legats_by_deadline(list)
      end

      def low_priority_count
        legats.count { |entry| entry["low_priority"] }
      end

      def batch_pending?(batch_name, require_sendable: false)
        batch = YAML.load_file(BPLAN_ROOT.join("legats/batches.yml")).dig("batches", batch_name, "ids") || []
        sent_ids = sent_log_ids
        batch.any? do |id|
          entry = legat(id)
          next false unless entry
          next false if require_sendable && !sendable?(entry)

          !sent_ids.include?(id)
        end
      rescue StandardError
        false
      end

      def bolig_asap_pending?
        batch_pending?("bolig_asap", require_sendable: true)
      end

      def bolig_portal_sept_pending?
        batch_pending?("bolig_portal_sept")
      end

      def sent_log_ids
        path = BPLAN_ROOT.join("legats/sent_log.yml")
        return [] unless path.file?

        log = YAML.load_file(path)
        raw = log["sent"]
        case raw
        when Hash then raw.keys
        when Array then raw.filter_map { |e| e["id"] if e.is_a?(Hash) }
        else []
        end
      end

      def deadline_urgent?(entry, today: funding["generated"].to_s)
        date_s = entry["date"].to_s
        return false if date_s.empty?

        begin
          d = Date.parse(date_s)
          t = Date.parse(today)
          (d - t).to_i.between?(0, 7)
        rescue ArgumentError
          false
        end
      end

      def legats_by_deadline(list = legats)
        list.sort_by { |entry| legat_deadline_sort_key(entry) }
      end

      def legat_deadline_sort_key(entry)
        deadline = entry["deadline"].to_s
        if (match = deadline.match(/(\d{4}-\d{2}-\d{2})/))
          [0, match[1]]
        elsif deadline.match?(/fortløpende|løpende/i)
          [1, "0000-00-00"]
        else
          [2, deadline.downcase]
        end
      end

      def legat(id)
        legats.find { |e| e["id"] == id.to_s }
      end

      def tracks
        legats.map { |entry| entry["track"] }.compact.uniq.sort
      end

      def sendable?(entry)
        return false unless entry["sendable"]
        return false if entry["draft"]
        return false if innovasjon_norge_blocked?(entry)

        true
      end

      def innovasjon_norge_blocked?(entry)
        return false if Bplan::Constants::INNOVASJON_NO_SENDABLE

        funder = entry["funder"].to_s
        id = entry["id"].to_s
        funder.include?("Innovasjon Norge") || id.include?("innovasjon_norge")
      end

      def attachment_checklist(entry)
        items = ["Signert søknad (PDF eller HTML)"]
        items << "Verifiser mottaker på giverens nettside" if entry["verify_to"]
        items << "Forretningsplan / prosjektbeskrivelse" if entry["project"].present?

        case entry["track"]
        when "bolig"
          items += ["Bostedsattest", "Skatteligning / skatteoppgjør", "Legeattest (dersom påkrevd)"]
        when "innovasjon", "helse"
          items += ["Budsjett og finansieringsplan", "CV / kompetanseoversikt"]
        when "finans"
          items += ["Finanstilsynet-vurdering (utkast)", "Åpen metodikk / risikodokumentasjon"]
        else
          items << "CV og kort motivasjon"
        end

        items << entry["notes"] if entry["notes"].present?
        items.uniq
      end

      def plan_html(slug)
        document_body("#{slug}.html")
      end

      def legat_html(id)
        entry = legat(id)
        return unless entry

        relative = entry["file"].to_s.delete_prefix("legats/")
        document_body("legats/#{relative}")
      end

      def document_body(relative_path)
        path = BPLAN_ROOT.join(relative_path)
        return unless path.file? && path.realpath.to_s.start_with?(BPLAN_ROOT.to_s)

        mtime = path.mtime.to_i
        cache_key = "#{relative_path}:#{mtime}"
        document_cache[cache_key] ||= sanitize_content(extract_content(path.read))
      end

      def extract_content(html)
        match = html.match(%r{<div class="content">(.*?)</div>\s*<footer>}m)
        body = match ? match[1].strip : html
        fix_asset_paths(body)
      end

      def sanitize_content(html)
        stripped = html.gsub(%r{<script\b[^>]*>.*?</script>}im, "")
                       .gsub(%r{<script\b[^>]*/>}i, "")
        if defined?(Rails::Html::SafeListSanitizer)
          Rails::Html::SafeListSanitizer.new.sanitize(
            stripped,
            tags: %w[h1 h2 h3 h4 p ul ol li table tr td th strong em a img figure div span time br],
            attributes: %w[href src alt class datetime loading data-plan role],
          )
        else
          stripped
        end
      end

      def fix_asset_paths(html)
        prefix = ASSET_PREFIX
        html
          .gsub('href="htu/', "href=\"#{prefix}/htu/")
          .gsub('src="htu/', "src=\"#{prefix}/htu/")
          .gsub('href="../htu/', "href=\"#{prefix}/htu/")
          .gsub('src="../htu/', "src=\"#{prefix}/htu/")
          .gsub('href="/bplan_data/', "href=\"#{prefix}/")
          .gsub('src="/bplan_data/', "src=\"#{prefix}/")
          .gsub('src="assets/', "src=\"#{prefix}/assets/")
          .gsub('src="../assets/', "src=\"#{prefix}/assets/")
      end

      def pay_amount_for(slug, kind: "legat")
        plan = plan(slug)
        return 0 unless plan

        kind == "in" ? plan[:ask_in_nok] : plan[:ask_legat_nok]
      end

      def show_in_pay?(plan)
        return false if plan[:slug] == "norwegian_hedge"
        return false unless plan[:ask_in_nok].positive?

        true
      end

      def portfolio_summary_html
        require File.expand_path("../../../funding_helpers.rb", __dir__)
        FundingHelpers.portfolio_summary_block(funding)
      end

      def portfolio_json
        portfolio = funding.fetch("portfolio", {})
        econ = funding.fetch("economics", {})
        {
          convergence_version: convergence_version,
          anti_double_dip: portfolio.fetch("anti_double_dip", []),
          realistic_ceiling_nok: portfolio.fetch("realistic_ceiling_nok", {}),
          startlan_bergen: portfolio.fetch("startlan_bergen", {}),
          economics: {
            monthly_minimum_living_nok: econ["monthly_minimum_living_nok"],
            legat_typical_range_nok: econ["legat_typical_range_nok"],
          },
        }
      end

      def deadline_calendar_html(limit: nil)
        require File.expand_path("../../../funding_helpers.rb", __dir__)
        FundingHelpers.deadline_calendar_block(funding, limit: limit)
      end

      def deadlines
        funding.fetch("deadlines", [])
      end

      def deadlines_ics
        lines = [
          "BEGIN:VCALENDAR",
          "VERSION:2.0",
          "PRODID:-//BPLAN//Deadlines//NB",
          "CALSCALE:GREGORIAN",
          "METHOD:PUBLISH",
          "X-WR-CALNAME:BPLAN frister",
        ]
        deadlines.each do |entry|
          uid = "#{entry['funder'].to_s.parameterize}-#{entry['date']}"
          dtstart = entry["date"].to_s.delete("-")
          summary = entry["funder"]
          description = [entry["action"], entry["verify_url"]].compact.join(" — ")
          lines += [
            "BEGIN:VEVENT",
            "UID:#{uid}@bplan.pub.healthcare",
            "DTSTART;VALUE=DATE:#{dtstart}",
            "SUMMARY:#{summary}",
            "DESCRIPTION:#{description.gsub("\n", '\\n')}",
            "URL:#{entry['verify_url']}",
            "END:VEVENT",
          ]
        end
        lines << "END:VCALENDAR"
        lines.join("\r\n")
      end

      def sitemap_xml
        urls = [BASE_URL + "/"]
        plans.each { |p| urls << "#{BASE_URL}/plans/#{p[:slug]}" }
        legats.each { |l| urls << "#{BASE_URL}/legats/#{l['id']}" }
        urls += [
          "#{BASE_URL}/portfolio",
          "#{BASE_URL}/deadlines",
          "#{BASE_URL}/plans",
          "#{BASE_URL}/legats",
        ]
        body = urls.uniq.map do |url|
          "  <url><loc>#{url}</loc></url>"
        end.join("\n")
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          #{body}
          </urlset>
        XML
      end

      def robots_txt
        <<~TXT
          User-agent: *
          Allow: /
          Sitemap: #{BASE_URL}/sitemap.xml
        TXT
      end

      def reload!
        @funding = @manifest = nil
        @document_cache = {}
      end

      private

      def document_cache
        @document_cache ||= {}
      end
    end
  end
end