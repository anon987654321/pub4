# frozen_string_literal: true

module Executor
  class ToolResult
    ANSI_ESCAPE_SEQUENCE = /\e\[[0-9;]*[A-Za-z]/.freeze

    MAX_STORED_BYTES = 32_768
    PREVIEW_BYTES = 512
    SLICE_START = 0

    TRUNCATION_SEPARATOR = "\n...[truncated]...\n"
    NULL_BYTE = "\u0000"
    REPLACEMENT_CHAR = "�"
    DEFAULT_ENCODING = Encoding::UTF_8

    Payload = Struct.new(
      :stdout,
      :stderr,
      :exit_code,
      :duration_ms,
      :captured_at,
      keyword_init: true
    )

    def self.for_run(run_id)
      return [] unless defined?(::ToolCall)

      ::ToolCall
        .includes(:tool, :tool_result, :run)
        .where(run_id: run_id)
        .order(:id)
        .map(&:tool_result)
        .compact
    end

    def self.persist(tool_call_id:, payload:)
      return unless defined?(::ToolCall)

      tool_call = ::ToolCall.includes(:tool_result).find(tool_call_id)
      normalized = normalize_payload(payload)

      if tool_call.respond_to?(:tool_result) && tool_call.tool_result
        tool_call.tool_result.update!(normalized)
        tool_call.tool_result
      elsif defined?(::ToolResultRecord)
        ::ToolResultRecord.create!(normalized.merge(tool_call_id: tool_call.id))
      else
        tool_call.create_tool_result!(normalized)
      end
    end

    def self.normalize_payload(payload)
      payload_hash = payload.is_a?(Payload) ? payload.to_h : payload.to_h

      stdout = normalize_shell(payload_hash[:stdout])
      stderr = normalize_shell(payload_hash[:stderr])

      {
        stdout: stdout,
        stderr: stderr,
        exit_code: payload_hash[:exit_code],
        duration_ms: payload_hash[:duration_ms],
        captured_at: payload_hash[:captured_at]
      }
    end

    def self.normalize_shell(text)
      return "" if text.nil?

      normalized = to_utf8(text.to_s)
      normalized = normalized.delete(NULL_BYTE).gsub(ANSI_ESCAPE_SEQUENCE, "")
      normalized = normalized.gsub("\r\n", "\n").gsub("\r", "\n")

      return normalized unless normalized.bytesize > MAX_STORED_BYTES

      truncated_prefix = normalized.byteslice(SLICE_START, PREVIEW_BYTES) || ""
      truncated_suffix = normalized.byteslice(-PREVIEW_BYTES, PREVIEW_BYTES) || ""

      [
        truncated_prefix,
        TRUNCATION_SEPARATOR,
        truncated_suffix
      ].join
    end

    def self.to_utf8(string)
      return string if string.encoding == DEFAULT_ENCODING && string.valid_encoding?

      string.encode(
        DEFAULT_ENCODING,
        invalid: :replace,
        undef: :replace,
        replace: REPLACEMENT_CHAR
      )
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      string.force_encoding(DEFAULT_ENCODING).scrub(REPLACEMENT_CHAR)
    end

    private_class_method :to_utf8
  end
end