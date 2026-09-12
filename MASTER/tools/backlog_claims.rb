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

TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze

# A verdict already written into the item — these have been decided.
DECIDED = /\*\*(?:Fixed|Done|Already|Closed|Declined|Overtaken|Measured|False|Partly|Argued|Held|Confirmed)\b/i

PATH_LINE = %r{\b((?:MASTER|RAILS|OPENBSD|STUDIO)?/?[\w./-]+\.(?:rb|yml|yaml|scss|css|js|mjs|erb|md|sh|rake|json|conf|zone))[:#](\d+)\b}
BARE_PATH = %r{\b((?:MASTER|RAILS|OPENBSD|STUDIO)/[\w./-]+\.(?:rb|yml|yaml|scss|css|js|mjs|erb|md|sh|rake|json|conf))\b}

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

BacklogClaims.run if $PROGRAM_NAME == __FILE__
