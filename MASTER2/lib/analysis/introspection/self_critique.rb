# frozen_string_literal: true

require "json"

module Analysis
  module Introspection
    class SelfCritique
      DEFAULT_MAX_FINDINGS = 5
      RESPONSE_SNIPPET_LENGTH = 200
      SLICE_START_INDEX = 0
      CODE_FENCE = "```"
      JSON_OBJECT_START = "{"
      JSON_OBJECT_END = "}"

      def initialize(model_client:, max_findings: DEFAULT_MAX_FINDINGS)
        @model_client = model_client
        @max_findings = max_findings
      end

      def critique_response(response_text)
        return [] if response_text.nil? || response_text.strip.empty?

        critique_payload = request_self_critique(response_text)
        critique_data = parse_json_object(critique_payload)
        normalize_findings(critique_data)
      end

      private

      attr_reader :model_client, :max_findings

      def request_self_critique(response_text)
        prompt = build_prompt(response_text)
        model_client.call(prompt)
      end

      def build_prompt(response_text)
        snippet = response_text[SLICE_START_INDEX, RESPONSE_SNIPPET_LENGTH].to_s
        <<~PROMPT
          You are reviewing an assistant response for quality issues.
          Return ONLY valid JSON with keys: findings (array).
          Each finding: { "category": "...", "detail": "...", "severity": "low|medium|high" }.

          Response snippet:
          #{CODE_FENCE}
          #{snippet}
          #{CODE_FENCE}
        PROMPT
      end

      def parse_json_object(text)
        json_text = extract_json_object(text)
        return {} if json_text.nil?

        JSON.parse(json_text)
      rescue JSON::ParserError
        {}
      end

      def extract_json_object(text)
        return nil if text.nil?

        stripped = text.strip
        return stripped if stripped.start_with?(JSON_OBJECT_START) && stripped.end_with?(JSON_OBJECT_END)

        start_idx = stripped.index(JSON_OBJECT_START)
        end_idx = stripped.rindex(JSON_OBJECT_END)
        return nil if start_idx.nil? || end_idx.nil? || end_idx < start_idx

        stripped[start_idx..end_idx]
      end

      def normalize_findings(critique_data)
        findings = critique_data.is_a?(Hash) ? critique_data["findings"] : nil
        findings = [] unless findings.is_a?(Array)

        findings.first(max_findings).map do |finding|
          normalize_finding(finding)
        end
      end

      def normalize_finding(finding)
        finding_hash = finding.is_a?(Hash) ? finding : {}
        {
          "category" => finding_hash["category"].to_s,
          "detail" => finding_hash["detail"].to_s,
          "severity" => normalize_severity(finding_hash["severity"])
        }
      end

      def normalize_severity(severity)
        value = severity.to_s.downcase
        return value if %w[low medium high].include?(value)

        "low"
      end
    end
  end
end