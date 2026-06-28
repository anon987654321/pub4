# frozen_string_literal: true

require "digest"

module Master
  module Reach
    # Hash-anchored line ids for stale-edit rejection (opencrabs hashline_edit).
    module Hashline
      ID_LENGTH = 2

      module_function

      def line_id(line) = Digest::SHA256.hexdigest(line.to_s.chomp)[0, ID_LENGTH]

      def format_lines(lines, offset: 0)
        lines.each_with_index.map do |line, index|
          number = offset + index + 1
          "#{number}##{line_id(line)}\t#{line}"
        end.join
      end

      def parse_anchor(value)
        match = value.to_s.strip.match(/\A(\d+)#([0-9a-f]{#{ID_LENGTH}})\z/i)
        return unless match

        { line: match[1].to_i, id: match[2].downcase }
      end

      def valid?(content, line_no:, id:)
        lines = content.lines
        return false if line_no < 1 || line_no > lines.size

        line_id(lines[line_no - 1].chomp) == id.to_s.downcase
      end

      def replace_line(content, line_no:, id:, new_line:)
        return Result.err("hashline: stale anchor #{line_no}##{id}", category: :validation) unless valid?(content, line_no:, id:)

        lines = content.lines
        lines[line_no - 1] = new_line.to_s.end_with?("\n") ? new_line : "#{new_line}\n"
        Result.ok(lines.join)
      end
    end
  end
end
