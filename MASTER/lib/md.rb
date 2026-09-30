# frozen_string_literal: true

module Master
  # Canonical Markdown normalization and source-side checks.
  #
  # Markdown is the source format. HTML and PDF are derived renderings; this
  # module changes only Markdown presentation and never edits fenced code.
  module MD
    Issue = Struct.new(:line, :code, :message, keyword_init: true)

    FENCE = /\A\s{0,3}(`{3,}|~{3,})/.freeze
    HEADING = /\A {0,3}\#{1,6}(?:\s|$)/.freeze
    BULLET = /\A(\s{0,3})[*+](\s+)/.freeze

    module_function

    def normalize(source)
      lines = source.to_s.gsub("\r\n", "\n").gsub("\r", "\n").split("\n", -1)
      output = []
      fence = nil

      lines.each do |raw|
        line = raw
        match = line.match(FENCE)

        if fence
          output << line
          fence = nil if match && match[1][0] == fence && match[1].length >= 3
          next
        end

        if match
          fence = match[1][0]
          output << line
          next
        end

        line = line.rstrip
        line = line.sub(BULLET, "\\1-\\2")
        line = "" if line.strip.empty?

        output << "" if HEADING.match?(line) && !output.empty? && !output.last.empty?
        output << line
      end

      output.pop while output.last == ""
      ensure_heading_breath(output)
      output.join("\n") + "\n"
    end

    def lint(source)
      normalized = normalize(source)
      return [] if normalized == source

      [
        Issue.new(
          line: first_difference_line(source.to_s, normalized),
          code: "MD001",
          message: "Markdown source can be normalized without changing fenced code."
        )
      ]
    end

    def file(path)
      normalize(File.read(path, encoding: "UTF-8"))
    end

    def write!(path)
      File.write(path, file(path), encoding: "UTF-8")
    end

    def style(root: Master::ROOT)
      Master.law("markdown_style", root:)
    rescue KeyError
      {}
    end

    def first_difference_line(left, right)
      left_lines = left.split("\n", -1)
      right_lines = right.split("\n", -1)
      [left_lines.size, right_lines.size].min.times do |index|
        return index + 1 if left_lines[index] != right_lines[index]
      end
      [left_lines.size, right_lines.size].min + 1
    end
    private_class_method :first_difference_line

    def ensure_heading_breath(lines)
      out = []
      lines.each_with_index do |line, index|
        out << "" if HEADING.match?(line) && index.positive? && out.last != ""
        out << line
        next unless HEADING.match?(line)

        following = lines[index + 1]
        out << "" if following && !following.empty?
      end
      lines.replace(out)
    end
    private_class_method :ensure_heading_breath
  end
end
