# frozen_string_literal: true

require "digest"
require "json"

module Master
  module Trace
    # Converts event payloads into safe durable records without changing the
    # in-process payload delivered to trusted subscribers. Tool arguments are
    # never stored verbatim; other event families redact sensitive named fields.
    module EventPrivacy
      TOOL_ARGUMENT_EVENTS = %w[tool:before tool:after tool:execution:before tool:execution:after tool:execution:reconciled].freeze
      SAFE_CATEGORIES = %w[
        event tool op operation tier profile mode risk status outcome capability verb
        stage state kind method reason_code invocation_id run_id mission_id attempt_id
        effect_id parent_effect_id checkpoint_id idempotency_key reconciliation evidence_ref
      ].freeze
      SAFE_NUMBERS = %w[
        ts pid schema_version bytes count elapsed_ms duration_ms result_bytes attempt attempts turn turns checks_ran
        failure_count warning_count unchecked_count n_handlers paths_count tracked_paths
      ].freeze
      SAFE_BOOLEANS = %w[blocked success ok cancelled complete enabled retry_requires_reconciliation].freeze
      FIELD_NAME = /\A[a-zA-Z][a-zA-Z0-9_]{0,63}\z/
      CATEGORY_VALUE = /\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,79}\z/
      SHA256 = /\A[0-9a-f]{64}\z/i
      SENSITIVE_FIELD = /(?:\A|_)(?:arg|args|argv|body|branch|command|content|cookie|credential|credentials|cwd|data|description|detail|dir|directory|error|exception|file|filename|goal|input|message|new|old|output|path|paths|payload|prompt|query|reason|ref|response|result|root|scope|secret|summary|target|text|token|transcript|uri|url|working_dir|working_directory|authorization|password|scan_ip|ip_address)(?:\z|_)/i

      module_function

      def persisted(event, payload)
        name = event.to_s
        source = payload.respond_to?(:to_h) ? payload.to_h : {}
        tool_event = TOOL_ARGUMENT_EVENTS.include?(name)

        source.each_with_object({}) do |(key, value), safe|
          field = key.to_s
          next if field == "conversation"
          next unless FIELD_NAME.match?(field)

          if safe_metadata?(field, value)
            safe[field.to_sym] = normalize_metadata(field, value)
          elsif tool_event || field.match?(SENSITIVE_FIELD)
            raw = canonical_value(value)
            safe["#{field}_digest".to_sym] = Digest::SHA256.hexdigest(raw)
            safe["#{field}_bytes".to_sym] = raw.bytesize
          else
            safe[field.to_sym] = value
          end
        end
      end

      def safe_metadata?(field, value)
        return true if SAFE_CATEGORIES.include?(field) && category_value?(value)
        return true if SAFE_NUMBERS.include?(field) && numeric_value?(value)
        return true if SAFE_BOOLEANS.include?(field) && [true, false].include?(value)
        return true if field.end_with?("_digest") && value.is_a?(String) && SHA256.match?(value)
        return true if field.end_with?("_bytes") && numeric_value?(value) && value >= 0

        false
      end

      def normalize_metadata(field, value)
        return value if SAFE_NUMBERS.include?(field) || SAFE_BOOLEANS.include?(field)

        value.to_s
      end

      def category_value?(value)
        (value.is_a?(String) || value.is_a?(Symbol)) && CATEGORY_VALUE.match?(value.to_s)
      end

      def numeric_value?(value)
        value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
      end

      def canonical_value(value)
        value.is_a?(String) ? value : JSON.generate(value)
      rescue StandardError
        value.class.name.to_s
      end
    end
  end
end
