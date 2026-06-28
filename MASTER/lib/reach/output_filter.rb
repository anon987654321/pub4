# frozen_string_literal: true

require "fileutils"
require "json"

module Master
  module Reach
    # Conservative shell-output compression before context ingest (RTK-inspired).
    module OutputFilter
      REL_STATS = "runtime/rtk_stats.json".freeze
      GIT_STATUS_RE = /\A(?:##[^\n]*\n)?(?:[ MADRCU?!]{1,3} .+\n)+\z/m.freeze

      module_function

      def filter(command:, output:)
        text = output.to_s
        return text if text.empty?

        cmd = command.to_s
        filtered =
          if cmd.match?(/\bgit\s+(?:status|diff|log)\b/)
            compress_git(text, cmd)
          elsif cmd.match?(/\b(?:ls|tree)\b/)
            compress_listing(text)
          elsif text.lines.size > 80
            head_tail(text, keep: 40)
          else
            text
          end

        record_saved(raw_bytes: text.bytesize, filtered_bytes: filtered.bytesize, command: cmd) if filtered != text
        filtered
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
        return text if lines.size <= 24

        if command.include?("diff") && text.bytesize > 2_000
          return "#{lines.first(12).join}[...diff truncated #{lines.size} lines / #{text.bytesize}B...]\n#{lines.last(4).join}"
        end

        head_tail(text, keep: 16)
      end

      def compress_listing(text)
        lines = text.lines
        return text if lines.size <= 30

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
