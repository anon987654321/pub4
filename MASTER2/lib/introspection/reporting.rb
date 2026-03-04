# frozen_string_literal: true

module Introspection
  module Reporting
    MASTER2 = "MASTER2"
    SELF_APPLY = MASTER2

    DEFAULTS = {
      title: nil,
      include_header: true,
      include_sections: true,
      include_actions: true
    }.freeze

    SECTION_ORDER = %i[overview findings actions metadata].freeze

    LABELS = {
      overview: "Overview",
      findings: "Findings",
      actions: "Recommended actions",
      metadata: "Metadata"
    }.freeze

    def print_prose_summary(report, opts = {})
      options = DEFAULTS.merge(opts || {})
      return "" unless report

      sections = build_sections(report, options)
      return "" if sections.empty?

      header = build_header(report, options)
      body = sections.join("\n\n")

      [header, body].compact.reject(&:empty?).join("\n\n")
    end

    private

    def build_header(report, options)
      return "" unless options.fetch(:include_header, true)

      title = options.fetch(:title, nil) || report.fetch(:title, nil) || "Summary"
      identity = report.fetch(:identity, nil)
      identity = SELF_APPLY if identity == "MASTER"

      header_lines = []
      header_lines << title.to_s
      header_lines << "Identity: #{identity}" if identity && !identity.to_s.empty?

      generated_at = report.fetch(:generated_at, nil)
      header_lines << "Generated at: #{generated_at}" if generated_at

      header_lines.compact.join("\n")
    end

    def build_sections(report, options)
      return [] unless options.fetch(:include_sections, true)

      data = normalize_report(report)
      SECTION_ORDER.filter_map do |section_key|
        next unless data.key?(section_key)

        section_text = format_section(section_key, data[section_key], options)
        section_text unless section_text.empty?
      end
    end

    def normalize_report(report)
      {
        overview: normalize_overview(report.fetch(:overview, nil)),
        findings: normalize_findings(report.fetch(:findings, nil)),
        actions: normalize_actions(report.fetch(:actions, nil)),
        metadata: normalize_metadata(report.fetch(:metadata, nil))
      }.compact
    end

    def format_section(key, payload, options)
      label = LABELS.fetch(key, key.to_s.capitalize)
      lines = []

      lines << label
      lines << "-" * label.length
      lines.concat(format_payload_lines(key, payload, options))

      lines = strip_blank_edges(lines)
      lines.join("\n")
    end

    def format_payload_lines(key, payload, options)
      case key
      when :overview
        Array(payload).map { |line| wrap_line(line.to_s) }
      when :findings
        format_findings(payload)
      when :actions
        return [] unless options.fetch(:include_actions, true)

        format_actions(payload)
      when :metadata
        format_metadata(payload)
      else
        Array(payload).map { |line| wrap_line(line.to_s) }
      end
    end

    def format_findings(findings)
      list = Array(findings).compact
      return ["(none)"] if list.empty?

      list.flat_map.with_index(1) do |item, idx|
        format_bulleted_item(item, idx)
      end
    end

    def format_actions(actions)
      list = Array(actions).compact
      return ["(none)"] if list.empty?

      list.flat_map.with_index(1) do |item, idx|
        format_bulleted_item(item, idx, prefix: "Action")
      end
    end

    def format_metadata(metadata)
      hash = metadata.is_a?(Hash) ? metadata : {}
      return ["(none)"] if hash.empty?

      hash.keys.sort.map do |k|
        v = hash.fetch(k, nil)
        wrap_line("#{k}: #{v}")
      end
    end

    def normalize_overview(overview)
      return nil if overview.nil?

      overview.is_a?(String) ? overview.split("\n").map(&:strip) : Array(overview)
    end

    def normalize_findings(findings)
      return nil if findings.nil?

      Array(findings)
    end

    def normalize_actions(actions)
      return nil if actions.nil?

      Array(actions)
    end

    def normalize_metadata(metadata)
      return nil if metadata.nil?

      metadata.is_a?(Hash) ? metadata : { value: metadata }
    end

    def format_bulleted_item(item, idx, prefix: nil)
      text = item.is_a?(Hash) ? item.fetch(:text, item.fetch("text", item.inspect)) : item.to_s
      tag = prefix ? "#{prefix} #{idx}" : idx.to_s

      lines = []
      lines << "#{tag}. #{wrap_line(text)}"

      details = item.is_a?(Hash) ? (item.fetch(:details, item.fetch("details", nil)) || []) : []
      Array(details).compact.each do |d|
        lines << "   - #{wrap_line(d.to_s)}"
      end

      lines
    end

    def wrap_line(text, width = 100)
      s = text.to_s.strip
      return "" if s.empty?
      return s if s.length <= width

      s.scan(/.{1,#{width}}(?:\s+|$)/).map(&:strip).join("\n")
    end

    def strip_blank_edges(lines)
      out = lines.dup
      out.shift while out.first&.strip&.empty?
      out.pop while out.last&.strip&.empty?
      out
    end
  end
end