# frozen_string_literal: true

module Studio
  # The table of contents of a large single-file tool: every top-level module and class with its
  # line number, and the banner comments that mark where a former file's code begins. It reads the
  # file as text, so it names the sections an editor or a reader jumps to and never loads the tool.
  module SourceMap
    ENTRY = /\A(?:(module|class)\s+([A-Z]\w*(?:::\w+)*)|(def)\s+(\w+[?!]?)|#\s*---\s+(\S.*?)\s+---\s*\z)/

    module_function

    # [[line, kind, name], ...] in file order; kind is "module", "class", "def" (a method at the left
    # margin) or "section".
    def entries(path)
      File.foreach(path).with_index(1).filter_map do |line, number|
        match = ENTRY.match(line.chomp) or next
        kind = match[1] || match[3]
        kind ? [number, kind, match[2] || match[4]] : [number, "section", match[5]]
      end
    end

    def render(path)
      rows = entries(path)
      width = rows.empty? ? 1 : rows.last.first.to_s.size
      title = "#{File.basename(path)}: #{File.foreach(path).count} lines, #{rows.size} sections"
      ([title] + rows.map { |number, kind, name| format("  %#{width}d  %-7s %s", number, kind, name) }).join("\n")
    end
  end
end
