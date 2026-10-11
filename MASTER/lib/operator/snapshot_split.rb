# frozen_string_literal: true

require "ripper"
require_relative "snapshot_minify"

module Operator

  # Cuts one file larger than a snapshot part into consecutive chunks whose concatenation is the
  # file byte for byte. A cut falls on a line that starts a top-level construct: a statement (or a
  # method of a class or module body) in Ruby, a rule outside any braces in CSS and SCSS, a column-0
  # line after a blank line in anything else. When no such line lies within twice the limit the cut
  # falls on a line boundary, never inside a line.
  module SnapshotSplit
    # A cut earlier than this fraction of the limit is passed over for a later one up to the 2x reach.
    MIN_FILL = 4

    module_function

    # The first chunk may have its own, smaller limit: the room left in the part the file starts in.
    def chunks(path, body, limit, first: limit)
      return [body] if body.bytesize <= first

      lines = body.lines
      starts = line_starts(lines)
      boundaries = candidates(path, body, lines)
      cuts = []
      from = 0

      loop do
        reach = cuts.empty? ? first : limit
        break if starts.last - starts[from] <= reach

        cut = pick(boundaries, starts, from, reach) || line_cut(starts, from, reach)
        cuts << cut
        from = cut
      end

      pieces = (cuts.unshift(0) << lines.size).each_cons(2).map { |a, b| lines[a...b].join }
      pieces.reject(&:empty?)
    end

    # Byte offset of each line start, and the total at the end.
    def line_starts(lines)
      offset = 0
      lines.map { |line| offset.tap { offset += line.bytesize } } << offset
    end

    # The last boundary that keeps the chunk within the limit; failing a worthwhile one, the last within twice it.
    def pick(boundaries, starts, from, limit)
      within = boundaries.select { |b| b > from && starts[b] - starts[from] <= limit * 2 }
      near = within.select { |b| starts[b] - starts[from] <= limit }
      best = near.last
      return best if best && starts[best] - starts[from] >= limit / MIN_FILL

      within.last || best
    end

    # No boundary within reach: the last whole line that fits, or the next line when one line alone is too long.
    def line_cut(starts, from, limit)
      fit = (from + 1...starts.size).take_while { |i| starts[i] - starts[from] <= limit }.last
      fit || from + 1
    end

    def candidates(path, body, lines)
      if ruby?(path, body)
        ruby_boundaries(body, lines)
      elsif %w[.css .scss].include?(File.extname(path).downcase)
        stylesheet_boundaries(body, lines)
      else
        column_zero_boundaries(lines)
      end
    end

    def ruby?(path, body)
      extension = File.extname(path).downcase
      return SnapshotMinify::HANDLERS[extension] == :ruby unless extension.empty?

      SnapshotMinify::NAMED_RUBY.include?(File.basename(path)) || body.lines.first.to_s.match?(/\A#!.*ruby/)
    end

    def column_zero_boundaries(lines)
      (1...lines.size).select { |i| lines[i - 1].strip.empty? && lines[i].match?(/\A\S/) }
    end

    # Line indexes (0-based) that start a statement of the program or of a class or module body.
    def ruby_boundaries(body, lines)
      sexp = Ripper.sexp(body)
      return column_zero_boundaries(lines) unless sexp

      found = []
      statements(sexp[1], -1, whole_line_comments(body, lines), found)
      found.uniq.select { |i| i.positive? && i < lines.size }.sort
    end

    # Statements in order, descending into class and module bodies so a long class cuts between
    # methods. A statement starts a chunk only when no earlier statement shares its line; the
    # comments directly above it stay with it.
    def statements(list, floor, comments, found)
      previous = floor
      Array(list).each do |node|
        next unless node.is_a?(Array) && node.first != :void_stmt

        extent = extent_of(node)
        next unless extent

        first, last = extent
        found << comment_start(first, previous, comments) if first > previous
        inner = container_body(node)
        statements(inner, first, comments, found) if inner
        previous = last
      end
    end

    def comment_start(line, previous, comments)
      line -= 1 while comments.include?(line - 1) && line - 1 > previous
      line
    end

    def container_body(node)
      case node.first
      when :class then node[3].is_a?(Array) && node[3].first == :bodystmt ? node[3][1] : nil
      when :module then node[2].is_a?(Array) && node[2].first == :bodystmt ? node[2][1] : nil
      end
    end

    # First and last source line of the positioned tokens inside a node.
    def extent_of(node)
      low = nil
      high = nil
      stack = [node]
      until stack.empty?
        item = stack.pop
        next unless item.is_a?(Array)

        if item.first.is_a?(Symbol) && item.first.to_s.start_with?("@") && item.last.is_a?(Array)
          line = item.last.first
          low = line if low.nil? || line < low
          high = line if high.nil? || line > high
        else
          stack.concat(item)
        end
      end

      low && [low - 1, high - 1]
    end

    def whole_line_comments(body, lines)
      Ripper.lex(body).filter_map do |(line, col), type, _tok, _state|
        line - 1 if type == :on_comment && lines[line - 1].to_s[0, col].strip.empty?
      end.to_set
    end

    # Lines at brace depth zero outside comments and strings that follow a finished rule or
    # declaration: the start of a rule, never the middle of a selector list.
    def stylesheet_boundaries(_body, lines)
      depth = 0
      in_comment = false
      finished = true
      boundaries = []

      lines.each_with_index do |line, index|
        boundaries << index if index.positive? && depth.zero? && !in_comment && finished && line.match?(/\S/)
        depth, in_comment = scan_css_line(line, depth, in_comment)
        finished = line.rstrip.end_with?("}", ";", "*/") || line.lstrip.start_with?("//") if line.match?(/\S/)
      end

      boundaries
    end

    def scan_css_line(line, depth, in_comment)
      quote = nil
      i = 0
      while i < line.size
        char = line[i]
        pair = line[i, 2]
        if in_comment
          if pair == "*/"
            in_comment = false
            i += 1
          end
        elsif quote
          i += 1 if char == "\\"
          quote = nil if char == quote
        elsif pair == "/*" then in_comment = true
        elsif pair == "//" then break
        elsif char == '"' || char == "'" then quote = char
        elsif char == "{" then depth += 1
        elsif char == "}" then depth -= 1
        end
        i += 1
      end

      [depth, in_comment]
    end
  end
end
