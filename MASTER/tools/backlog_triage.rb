# frozen_string_literal: true

# Which TODO.md items are still about this tree.
#
# The backlog holds 5,600 actionable-shaped entries and grows faster than anyone
# can work them. Of fourteen verified by hand on 2026-09-11, three were already
# done and three were false — so acting on the list unmeasured wastes about
# half the effort, and one item would have deleted five live commands.
#
# This does the mechanical half. An item that names a file says something
# checkable: the file exists or it does not, and a quoted symbol is in it or it
# is not. Nothing here judges whether a real finding is worth fixing — that is
# the reading this makes affordable by removing the items that cannot be.
#
#   ruby MASTER/tools/backlog_triage.rb             # the counts
#   ruby MASTER/tools/backlog_triage.rb --open      # items with a subject to check
#   ruby MASTER/tools/backlog_triage.rb --absent    # items naming no file in the tree
#
# A path is only checked when it looks like one this repo would hold. Prose
# naming a gem, a URL or another project is not a claim about our tree, and
# neither is a proposal with no file behind it yet — 5,024 of 5,741 items are in
# that position, which is the first thing worth knowing about this backlog.

require "English"

module Operator
  module BacklogTriage
    ROOT = File.expand_path("../..", __dir__)
    TODO = File.join(ROOT, "TODO.md")

    # A path we could own: one of the four trees, or a bare filename with an
    # extension this repo writes.
    TREE_PATH = %r{\b((?:MASTER|RAILS|OPENBSD|STUDIO)/[\w./-]+\.\w+)}
    BACKTICKED = /`([^`\n]{3,80})`/

    OWNED_EXTENSIONS = %w[.rb .erb .scss .css .js .mjs .yml .yaml .sh .ksh .md .json .html].freeze

    Item = Struct.new(:line_no, :text, :paths, keyword_init: true)

    class << self
      def run(argv)
        items = parse
        judged = items.map { |item| [item, verdict(item)] }

        case argv.first
        when "--absent" then print_items(judged, :absent)
        when "--open" then print_items(judged, :open)
        else print_counts(judged, items)
        end
      end

      # An item is a numbered entry or a bold bullet, plus its continuation
      # lines — a claim's evidence is usually on the line after the claim.
      def parse
        items = []
        current = nil

        File.readlines(TODO).each_with_index do |line, index|
          if line.match?(/\A\s{0,3}(?:\d+\.|[-*])\s+\S/)
            items << current if current
            current = Item.new(line_no: index + 1, text: line, paths: [])
          elsif current && line.match?(/\A\s{2,}\S/)
            current.text += line
          elsif line.strip.empty? && current
            items << current
            current = nil
          end
        end
        items << current if current

        items.each { |item| item.paths = paths_in(item.text) }
      end

      def paths_in(text)
        explicit = text.scan(TREE_PATH).flatten
        backticked = text.scan(BACKTICKED).flatten.select do |token|
          OWNED_EXTENSIONS.include?(File.extname(token)) && !token.include?(" ")
        end
        (explicit + backticked).uniq
      end

      # unanchored — names no file this repo owns, so nothing here can check it
      # absent     — names only files that are not in the tree
      # open       — names at least one file that is, so the claim has a subject
      #
      # absent is not closed, and telling the two apart needs the sentence.
      # "`mask.js` is dead weight" names a file since deleted, so it is done.
      # "Rename to `restore_litestream.sh`" names a file that does not exist
      # because the rename has not happened, so it is open. A path check reads
      # both the same way.
      def verdict(item)
        return :unanchored if item.paths.empty?

        resolved = item.paths.map { |path| locate(path) }
        # A glob describes a set rather than claiming one file exists.
        return :open if resolved.include?(:glob)
        return :absent if resolved.none?

        :open
      end

      # Most items are written from inside the tree they are about — `law/ruby.rb`
      # and `data/rules.yml` mean MASTER's, and `shared/_tokens.scss` means
      # RAILS'. Resolving only from the repo root called 198 live items stale on
      # the first run, which is the shape this repo keeps relearning: check what
      # the instrument measured before believing the finding.
      TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze

      def locate(path)
        # A glob is a description of a set, not a claim that one file exists.
        return :glob if path.include?("*")

        candidates = [path] + TREES.map { |tree| File.join(tree, path) }
        found = candidates.find { |rel| File.exist?(File.join(ROOT, rel)) }
        return File.join(ROOT, found) if found

        @index ||= tracked.group_by { |rel| File.basename(rel) }
        hit = @index[File.basename(path)]
        hit && File.join(ROOT, hit.first)
      end

      def tracked
        @tracked ||= begin
          listed = IO.popen(["git", "-C", ROOT, "ls-files"], &:read).split("\n")
          raise "backlog_triage: git ls-files failed" unless $CHILD_STATUS.success?

          listed
        end
      end

      def print_counts(judged, items)
        counts = judged.group_by { |_, verdict| verdict }.transform_values(&:size)
        puts "TODO.md: #{items.size} items"
        puts format("  %-12s %5d   names no file this repo owns", "unanchored", counts.fetch(:unanchored, 0))
        puts format("  %-12s %5d   names only files not in the tree", "absent", counts.fetch(:absent, 0))
        puts format("  %-12s %5d   names a file that exists", "open", counts.fetch(:open, 0))
        puts
        puts "--absent lists items whose files are missing: read each to tell a"
        puts "finished deletion from a rename that has not happened yet."
      end

      def print_items(judged, wanted)
        rows = judged.select { |_, verdict| verdict == wanted }
        rows.each do |item, _|
          first = item.text.lines.first.to_s.strip
          puts format("  TODO.md:%-6d %s", item.line_no, first[0, 104])
          puts format("            names: %s", item.paths.first(3).join(", "))
        end
        puts "# #{rows.size} #{wanted}"
      end
    end
  end
end

Operator::BacklogTriage.run(ARGV) if $PROGRAM_NAME == __FILE__
