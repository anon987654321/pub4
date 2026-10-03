# frozen_string_literal: true

module Master
  module Fix
    class Restructure
      PLAN_HEADER = /\A=== (WRITE|DELETE) (\S+)[ \t]*\z/

      # A model's restructure, parsed: files written in full and files deleted,
      # each named from the repository root. A move is a write and a delete,
      # and git sees the rename.
      Plan = Data.define(:summary, :writes, :deletes) do
        def self.parse(text)
          writes = {}
          deletes = []
          sections(text.to_s).each do |verb, path, body|
            verb == "WRITE" ? writes[path] = body : deletes << path
          end
          new(summary: text.to_s[/^SUMMARY:[ \t]*(.+)$/, 1].to_s.strip, writes:, deletes:)
        end

        # The text from the first header up to === END, cut at each header.
        def self.sections(text)
          start = text.index(/^=== (?:WRITE|DELETE) /) or return []
          body = text[start..].split(/^=== END[ \t]*$/, 2).first
          body.split(/(?=^=== (?:WRITE|DELETE) )/).filter_map do |chunk|
            head, rest = chunk.split("\n", 2)
            match = head.to_s.strip.match(PLAN_HEADER) or next
            [match[1], match[2], match[1] == "WRITE" ? "#{rest.to_s.sub(/\n+\z/, "")}\n" : nil]
          end
        end

        def paths = writes.keys + deletes
        def empty? = paths.empty?
      end
    end
  end
end
