# frozen_string_literal: true

require "digest"

module MASTER
  class Executor
    # ToolResult — the single schema every tool call produces.
    #
    # The LLM never sees raw tool output.  It only sees #to_prompt,
    # a compact, fact-based summary.  The raw string is stored for
    # audit/reproducibility but never injected into the model context.
    #
    # Contract (Liskov): every tool adapter must produce a ToolResult.
    # If a tool returns a plain String, ToolResult.normalize wraps it.
    class ToolResult
      attr_reader :tool, :raw, :facts, :exit_code, :files_touched,
                  :stderr_summary, :content_hash

      def initialize(tool:, raw:, facts: [], exit_code: nil,
                     files_touched: [], stderr_summary: nil)
        @tool          = tool.to_s
        @raw           = raw.to_s
        @facts         = Array(facts).map(&:to_s).reject(&:empty?)
        @exit_code     = exit_code
        @files_touched = Array(files_touched).map(&:to_s).reject(&:empty?).uniq
        @stderr_summary = stderr_summary
        @content_hash  = Digest::SHA256.hexdigest(@raw)[0, 12]
      end

      def blocked?
        @raw.start_with?("BLOCKED:")
      end

      def error?
        @raw.start_with?("Error:") || @raw.start_with?("Tool error:")
      end

      # What the LLM receives: structured facts, never raw output.
      def to_prompt
        lines = ["[tool=#{tool} hash=#{content_hash}]"]
        lines << "exit=#{exit_code}"                          if exit_code
        lines << "blocked: #{raw[8..200]}"                   if blocked?
        lines << "error: #{raw[0..200]}"                     if error? && !blocked?
        lines << "files: #{files_touched.join(', ')}"        if files_touched.any?
        lines << "stderr: #{stderr_summary[0..120]}"         if stderr_summary
        if facts.any?
          lines += facts.map { |f| "  #{f}" }
        elsif !blocked? && !error?
          # Fallback: bounded raw excerpt so the LLM is never context-free
          lines << raw[0..400]
          lines << "... (#{raw.length} chars, truncated)" if raw.length > 400
        end
        lines.join("\n")
      end

      # --- Normalizers --------------------------------------------------

      def self.normalize(tool_name, raw)
        raw_str = raw.to_s
        case tool_name.to_s
        when "shell_command", "code_execution" then normalize_shell(tool_name, raw_str)
        when "file_read"                        then normalize_file_read(tool_name, raw_str)
        when "file_write"                       then normalize_file_write(tool_name, raw_str)
        when "web_search", "browse_page"        then normalize_web(tool_name, raw_str)
        when "analyze_code", "fix_code"         then normalize_analysis(tool_name, raw_str)
        else                                         normalize_generic(tool_name, raw_str)
        end
      end

      def self.normalize_shell(tool_name, raw)
        facts         = []
        exit_code     = nil
        stderr_summary = nil
        files_touched = []

        if raw.start_with?("BLOCKED:", "Error:", "Tool error:")
          facts << raw[0..200]
        else
          # Exit code hint embedded in some outputs
          if (m = raw.match(/\bexit(?:_code)?[=:\s]+(\d+)/i))
            exit_code = m[1].to_i
          end
          # Files mentioned by common tools (rubocop, git, rake, minitest)
          raw.scan(/(?:modified|created|deleted|written|updated|Offenses in)[:\s]+([^\s\n,]+\.(?:rb|yml|sh|js|ts|erb|md))/i) do |m|
            files_touched << m[0]
          end
          # Surface summary lines (N runs, N errors, etc.)
          raw.scan(/\d+\s+(?:files?|errors?|warnings?|offenses?|tests?|runs?|assertions?)[^\n]*/i) do |m|
            facts << m.strip[0..120]
          end
          facts << "ok" if facts.empty? && !raw.strip.empty?
        end

        new(tool: tool_name, raw: raw, facts: facts, exit_code: exit_code,
            files_touched: files_touched, stderr_summary: stderr_summary)
      end

      def self.normalize_file_read(tool_name, raw)
        facts = if raw.start_with?("File not found")
                  [raw]
                elsif (m = raw.match(/(\d+) chars total/))
                  ["file read (#{m[1]} chars, truncated at #{Executor::MAX_FILE_CONTENT})"]
                else
                  ["file read (#{raw.length} chars)"]
                end
        new(tool: tool_name, raw: raw, facts: facts)
      end

      def self.normalize_file_write(tool_name, raw)
        facts         = []
        files_touched = []
        if (m = raw.match(/Written (\d+) bytes to (\S+)/))
          facts         << "wrote #{m[1]} bytes"
          files_touched << m[2]
        else
          facts << raw[0..200]
        end
        new(tool: tool_name, raw: raw, facts: facts, files_touched: files_touched)
      end

      def self.normalize_web(tool_name, raw)
        facts = if raw.match?(/\A(?:Search|Browse) failed/)
                  [raw[0..200]]
                else
                  summary = raw[0..300].split(/[.\n]/).first(3).join(". ").strip
                  [summary, "(#{raw.length} chars total)"].reject(&:empty?)
                end
        new(tool: tool_name, raw: raw, facts: facts)
      end

      def self.normalize_analysis(tool_name, raw)
        new(tool: tool_name, raw: raw, facts: [raw[0..300]])
      end

      def self.normalize_generic(tool_name, raw)
        facts = raw.empty? ? [] : [raw[0..300]]
        new(tool: tool_name, raw: raw, facts: facts)
      end
    end
  end
end
