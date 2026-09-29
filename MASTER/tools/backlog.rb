# frozen_string_literal: true

# Test what each backlog item asserts, rather than reading them one at a time.
#
# TODO.md carries 2245 numbered items. Working them individually is the honest
# way and it is also the slow way, and roughly a third of the ones worked by hand
# turned out to be wrong about the tree — a file since deleted, a line that moved,
# a string that is no longer there. Those are exactly the claims a machine can
# check, and an item whose own citation has gone stale should not cost a human
# read.
#
# Three kinds of citation are checkable:
#
#   path:line   the file exists and has that many lines
#   `literal`   a backticked token that looks like a path, constant or method
#   path        a bare path anywhere in the item
#
# Anything else is prose and is left alone. The output is a verdict per item, and
# the only one worth acting on in bulk is `stale`: the item names something the
# tree no longer has, so either the work is done or the item needs rewriting
# against what is there now.
#
# This does not close anything. It sorts 2245 items into a few hundred worth
# reading and the rest, which is the whole point.

require "set"

ROOT = File.expand_path("../..", __dir__)
TODO = File.join(ROOT, "TODO.md")

TREES = %w[MASTER RAILS OPENBSD].freeze

# A verdict already written into the item — these have been decided.
DECIDED = /\*\*(?:Fixed|Done|Already|Closed|Declined|Overtaken|Measured|False|Partly|Argued|Held|Confirmed)\b/i

PATH_LINE = %r{\b((?:MASTER|RAILS|OPENBSD)?/?[\w./-]+\.(?:rb|yml|yaml|scss|css|js|mjs|erb|md|sh|rake|json|conf|zone))[:#](\d+)\b}
BARE_PATH = %r{\b((?:MASTER|RAILS|OPENBSD)/[\w./-]+\.(?:rb|yml|yaml|scss|css|js|mjs|erb|md|sh|rake|json|conf))\b}

module BacklogClaims
  module_function

  def tracked
    @tracked ||= `git -C #{ROOT} ls-files`.lines.map(&:strip).to_set
  end

  # A citation may be repo-relative or tree-relative; try both before calling it
  # absent, because most items are written from inside their tree.
  def resolve(path)
    return path if tracked.include?(path)

    TREES.each do |tree|
      candidate = File.join(tree, path)
      return candidate if tracked.include?(candidate)
    end

    # A bare basename — `soul.yml`, `help.rb` — names a file whose directory the
    # reader is expected to know. Match it by suffix. One hit resolves; several
    # is ambiguous rather than absent, because picking the first would invent a
    # citation the item never made.
    suffix = tracked.select { |t| t.end_with?("/#{path}") }
    return suffix.first if suffix.size == 1

    suffix.empty? ? nil : :ambiguous
  end

  def line_count(path)
    @lines ||= {}
    @lines[path] ||= File.readlines(File.join(ROOT, path)).size
  rescue StandardError
    0
  end

  def items
    body = File.read(TODO)
    body.scan(/^(\d+)\. (\*\*.*?)(?=\n\d+\. \*\*|\n#{'#'}{2,} |\z)/m)
  end

  def verdict(text)
    return :decided if text.match?(DECIDED)

    pl = text.scan(PATH_LINE)
    unless pl.empty?
      stale = pl.filter_map do |(path, line)|
        resolved = resolve(path)
        next "#{path} (absent)" if resolved.nil?
        # A basename several tracked files share cannot be line-checked without
        # guessing which one the item meant.
        next if resolved == :ambiguous
        next "#{path}:#{line} (file has #{line_count(resolved)} lines)" if line.to_i > line_count(resolved)

        nil
      end
      return [:stale_citation, stale] unless stale.empty?

      return :citation_holds
    end

    paths = text.scan(BARE_PATH).flatten.uniq
    unless paths.empty?
      missing = paths.reject { |p| r = resolve(p); r && r != :ambiguous }
      return [:absent_path, missing] unless missing.empty?

      return :path_holds
    end

    :prose
  end

# Every identifier the tree defines, so an item's backticked tokens can be tested
# against it.
#
# What this CANNOT do, and the reason it reports a stratification rather than a
# verdict: a token the tree does not define is not thereby stale. Most of them are
# external vocabulary — PerformanceObserver, data-turbo-prefetch, aria-busy,
# prefers-reduced-motion are browser names; fresh_when and update_column are
# Rails. A first version called all 719 of those "identifiers the tree does not
# define", which is true and useless. Telling this tree's lost names from the
# world's live ones needs an allowlist of Rails, DOM and CSS vocabulary, and an
# allowlist nobody curates is where dead names hide.
#
# So the sound half is the positive one: an item whose every named identifier
# exists here is an item about live code, and can be worked now. That bucket is
# the working set.
def symbols
  @symbols ||= begin
    index = Set.new
    tracked.each do |path|
      next unless path.match?(/\.(rb|yml|yaml|scss|js|mjs|erb|rake)\z/)
      next if path.start_with?("snapshot_")

      index << File.basename(path)
      body = begin
        File.read(File.join(ROOT, path), encoding: "UTF-8")
      rescue StandardError
        next
      end

      body.scan(/^\s*(?:class|module)\s+([A-Z][\w:]*)/) { |(c)| index << c.split("::").last; index << c }
      body.scan(/^\s*def\s+(?:self\.)?([\w?!=\[\]<>+*\/-]+)/) { |(m)| index << m }
      body.scan(/^\s*([A-Z][A-Z0-9_]{2,})\s*=/) { |(c)| index << c }
      body.scan(/^\s{0,8}([a-z_][\w]*):\s/) { |(k)| index << k }
      body.scan(/^\s*(?:--)([\w-]+):/) { |(v)| index << "--#{v}" }
      body.scan(/^\s*\.([a-z][\w-]+)\s*[,{]/) { |(c)| index << ".#{c}" }
    end
    index
  end
end

CODE_TOKEN = /`([A-Za-z_.#-][\w:.#?!\/-]{2,})`/

def token_verdict(text)
  tokens = text.scan(CODE_TOKEN).flatten
               .reject { |t| t.include?(" ") }
               .map { |t| t.sub(/\A#/, "").sub(/[#.]\z/, "") }
               .reject(&:empty?)
               .uniq
               .reject { |t| t.include?("/") || t.match?(/\.\w{2,4}\z/) }
  return :no_code_token if tokens.empty?

  known = tokens.select { |t| symbols.include?(t) || symbols.include?(t.split(/[#.]/).last) }
  return :every_name_is_ours if known.size == tokens.size
  return :no_name_is_ours if known.empty?

  :mixed_names
end

def symbol_report
  tally = Hash.new(0)
  working_set = []

  items.each do |number, text|
    if text.match?(DECIDED)
      tally[:decided] += 1
      next
    end

    kind = token_verdict(text)
    tally[kind] += 1
    working_set << [number, text.lines.first.strip[0, 88]] if kind == :every_name_is_ours
  end

  puts "TODO.md: #{items.size} items, #{symbols.size} identifiers indexed from the tree"
  puts
  tally.sort_by { |_, n| -n }.each { |k, n| puts "  #{k.to_s.ljust(20)} #{n}" }
  puts
  puts "decided            — a verdict is already written into the item"
  puts "every_name_is_ours — every backticked identifier exists here: the working set"
  puts "mixed_names        — some ours, some external vocabulary; needs reading"
  puts "no_name_is_ours    — names only external vocabulary, or names something gone"
  puts "no_code_token      — prose with no code anchor at all"
  puts
  puts "Working set (#{working_set.size}):"
  working_set.first(Integer(ENV.fetch("LIMIT", "25"))).each { |n, head| puts "  #{n}. #{head}" }
  puts "  ... #{working_set.size - 25} more" if working_set.size > 25
end

# Which tree does an item belong to?
#
# This is the partition to split the backlog on when more than one agent works it,
# and it is not an arbitrary choice: `bin/operator hooks` installs a pre-commit
# that REFUSES a commit spanning more than one top-level tree. So a per-tree split
# is enforced by the repo itself — two agents on different trees cannot land in
# each other's commit, and each tree has its own test command, so neither blocks
# the other waiting for a suite.
#
# Splitting by bucket instead (prose vs testable) does not have that property: two
# agents would both be editing TODO.md and both touching RAILS.
#
# An item with no tree signal goes to :shared — TODO.md itself, or prose about the
# repo as a whole. Those are the ones to agree on by hand, and there are few.
def tree_of(text)
  hits = TREES.select { |t| text.include?("#{t}/") }
  return hits.first if hits.size == 1
  return :spans_trees if hits.size > 1

  # No explicit prefix: infer from vocabulary that is unambiguous per tree.
  return "RAILS" if text.match?(/\b(brgen|amber|bsdports|marketplace|takeaway|dating|radio|vertical|scss|erb|Stimulus|Turbo)\b/i)
  return "MASTER" if text.match?(/\b(dilla|postpro|replicate|lora|render|stem|bpm|sonic)\b/i)
  return "OPENBSD" if text.match?(/\b(vm23|relayd|nsd|acme|pf\.conf|rc\.d|crontab|deploy|doas)\b/i)
  return "MASTER" if text.match?(/\b(law|scanner|ratchet|council|fold|soul\.yml|rules\.yml|face|TTS)\b/i)

  :shared
end

def partition_report
  by_tree = Hash.new { |h, k| h[k] = [] }

  items.each do |number, text|
    next if text.match?(DECIDED)

    by_tree[tree_of(text)] << number
  end

  total = by_tree.values.sum(&:size)
  puts "#{total} undecided items, partitioned by the tree they touch."
  puts "The pre-commit hook refuses a commit spanning two trees, so this split is"
  puts "enforced rather than agreed: two agents on different trees cannot collide."
  puts
  by_tree.sort_by { |_, v| -v.size }.each do |tree, numbers|
    puts "  #{tree.to_s.ljust(12)} #{numbers.size.to_s.rjust(4)}"
  end
  puts
  puts "TODO.md itself is the one shared file — whoever edits it commits it with"
  puts "their own tree's change, and :spans_trees plus :shared are the items to"
  puts "divide by hand."
end

  def run
    tally = Hash.new(0)
    stale = []

    items.each do |number, text|
      v = verdict(text)
      kind = v.is_a?(Array) ? v.first : v
      tally[kind] += 1
      stale << [number, v.last, text.lines.first.strip[0, 96]] if v.is_a?(Array)
    end

    puts "TODO.md: #{items.size} numbered items"
    tally.sort_by { |_, n| -n }.each { |k, n| puts "  #{k.to_s.ljust(16)} #{n}" }

    return if stale.empty?

    puts "\nItems whose own citation no longer resolves (#{stale.size}):"
    stale.first(Integer(ENV.fetch("LIMIT", "40"))).each do |number, detail, head|
      puts "  #{number}. #{head}"
      puts "      #{Array(detail).join('; ')}"
    end
    puts "  ... #{stale.size - 40} more" if stale.size > 40
  end
end

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

    # A path we could own: one of the three top-level trees, or a bare filename with an
    # extension this repo writes.
    TREE_PATH = %r{\b((?:MASTER|RAILS|OPENBSD)/[\w./-]+\.\w+)}
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
      TREES = %w[MASTER RAILS OPENBSD].freeze

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
if $PROGRAM_NAME == __FILE__
  if ARGV.first == "--claims" || ARGV.first == "--partition" || ARGV.first == "--symbols"
    ARGV.shift
    ARGV.unshift("--partition") if ARGV.empty? && ARGV.first == "--claims"
    BacklogClaims.run
  else
    Operator::BacklogTriage.run(ARGV)
  end
end
