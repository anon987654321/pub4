# frozen_string_literal: true

require "fileutils"
require "json"
require "yaml"

module Master
  module Io
    # Conservative shell-output compression before context ingest (RTK-inspired).
    #
    # Shell and git output only. A JSON tool result stays out: head_tail keeps the
    # ends of a long text and cuts a JSON document into something that no longer
    # parses, so each JSON tool caps its own result instead.
    module OutputFilter
      REL_FILTERS = "data/rtk_filters.yml".freeze
      ERROR_RE = /\b(?:errors?|failed|failures?|fatal|exceptions?|panic|traceback|denied|cannot|can't|not found|offenses?)\b/i
      BLOCK_LINE_CAP = 20
      REL_STATS = "runtime/rtk_stats.json".freeze
      GENERIC_COMPRESS_LINE_COUNT = 80
      GIT_COMPRESS_LINE_COUNT = 24
      DIFF_COMPRESS_BYTES = 2_000
      LISTING_COMPRESS_LINE_COUNT = 30

      module_function

      def filter(command:, output:)
        text = output.to_s
        return text if text.empty?

        cmd = command.to_s
        return text unless enabled?

        filtered =
          if cmd.match?(/\bgit\s+(?:status|diff|log)\b/)
            compress_git(text, cmd)
          elsif cmd.match?(/\b(?:ls|tree)\b/)
            compress_listing(text)
          elsif (declared = declared_filter(text, cmd))
            declared
          elsif text.lines.size > GENERIC_COMPRESS_LINE_COUNT
            head_tail(text, keep: 40)
          else
            text
          end

        record_saved(raw_bytes: text.bytesize, filtered_bytes: filtered.bytesize, command: cmd) if filtered != text
        filtered
      end

      def enabled? = ENV["MASTER_RTK"] != "0"

      # A failing command's output, compressed by its declared filter, or nil when
      # none matches: the caller keeps its own tail then. Error lines survive.
      def compress_failure(command:, output:)
        return unless enabled?

        text = output.to_s
        text.empty? ? nil : declared_filter(text, command.to_s)
      end

      def specs
        @specs ||= Array(YAML.safe_load_file(File.join(Master::ROOT, REL_FILTERS)).fetch("filters")).map do |row|
          row.to_h { |key, value| [key.to_sym, value.is_a?(Array) ? value.map { |re| Regexp.new(re) } : value] }
            .tap { |spec| spec[:match] = Regexp.new(spec.fetch(:match)) }
        end
      end

      def reload! = (@specs = nil)

      def declared_filter(text, command)
        spec = specs.find { |candidate| candidate[:match].match?(command) }
        spec && apply_spec(text, spec)
      end

      def apply_spec(text, spec)
        state = { out: [], elided: 0, loose: 0, block: nil }
        lines = spec[:collapse_repeats] ? collapse_repeats(text.lines.map(&:chomp)) : text.lines.map(&:chomp)
        lines.each { |line| place(line, spec, state) }
        flush_elided(state)
        result = state[:out].join("\n")
        result << "\n" unless result.empty?
        result.bytesize < text.bytesize ? result : text
      end

      def collapse_repeats(lines)
        lines.chunk_while { |a, b| a.strip == b.strip && !a.strip.empty? }.flat_map do |run|
          run.size > 2 ? [run.first, "[... #{run.size - 1} identical lines elided ...]"] : run
        end
      end

      def place(line, spec, state)
        state[:block] = (spec[:blocks] || []).any? { |re| re.match?(line) } ? 0 : state[:block]
        state[:block] = nil if state[:block] && line.strip.empty?
        if protected_line?(line, spec, state)
          flush_elided(state)
          state[:out] << line
        elsif line.strip.empty?
          nil
        elsif droppable?(line, spec) || state[:loose] >= spec.fetch(:max_lines, 60)
          state[:elided] += 1
        else
          flush_elided(state)
          state[:out] << line
          state[:loose] += 1
        end
      end

      def protected_line?(line, spec, state)
        if state[:block]
          state[:block] += 1
          return true if state[:block] <= BLOCK_LINE_CAP
        end
        ERROR_RE.match?(line) || line.start_with?("[...") || (spec[:protect] || []).any? { |re| re.match?(line) }
      end

      def droppable?(line, spec)
        return true if (spec[:drop] || []).any? { |re| re.match?(line) }

        keep = spec[:keep_only]
        keep ? keep.none? { |re| re.match?(line) } : false
      end

      def flush_elided(state)
        return if state[:elided].zero?

        state[:out] << "[... #{state[:elided]} lines elided ...]"
        state[:elided] = 0
      end

      def stats(root)
        file = File.join(root, REL_STATS)
        return default_stats unless File.file?(file)

        JSON.parse(File.read(file))
      rescue StandardError
        default_stats
      end

      def default_stats
        { "bytes_in" => 0, "bytes_out" => 0, "commands" => 0, "saved_pct" => 0.0 }
      end

      def compress_git(text, command)
        lines = text.lines
        return text if lines.size <= GIT_COMPRESS_LINE_COUNT

        if command.include?("diff") && text.bytesize > DIFF_COMPRESS_BYTES
          return "#{lines.first(12).join}[...diff truncated #{lines.size} lines / #{text.bytesize}B...]\n#{lines.last(4).join}"
        end

        head_tail(text, keep: 16)
      end

      def compress_listing(text)
        lines = text.lines
        return text if lines.size <= LISTING_COMPRESS_LINE_COUNT

        "#{lines.first(20).join}[...#{lines.size - 25} lines omitted...]\n#{lines.last(5).join}"
      end

      def head_tail(text, keep:)
        lines = text.lines
        return text if lines.size <= keep * 2

        "#{lines.first(keep).join}[...#{lines.size - keep * 2} lines omitted...]\n#{lines.last(keep).join}"
      end

      def record_saved(raw_bytes:, filtered_bytes:, command:, root: Master::ROOT)
        saved = [raw_bytes - filtered_bytes, 0].max
        return if saved.zero?

        file = File.join(root, REL_STATS)
        FileUtils.mkdir_p(File.dirname(file))
        data = stats(root)
        data["bytes_in"] = data.fetch("bytes_in", 0) + raw_bytes
        data["bytes_out"] = data.fetch("bytes_out", 0) + filtered_bytes
        data["commands"] = data.fetch("commands", 0) + 1
        total_in = data["bytes_in"].to_f
        data["saved_pct"] = total_in.positive? ? ((total_in - data["bytes_out"]) / total_in * 100).round(1) : 0.0
        data["last_command"] = command.to_s[0, 120]
        File.write(file, JSON.generate(data))
        data
      end
    end
  end
end
