# frozen_string_literal: true

# Test what each backlog item asserts, rather than reading them one at a time.
#
# TODO.md is the single checkbox backlog. Keep this reader coupled to its
# current format: a numbered-list parser silently returned zero items after the
# backlog was consolidated. An empty report must never masquerade as a clean
# audit.
#
# Three kinds of citation are checked when an item names them:
#
#   path:line   the file exists and has that many lines
#   `literal`   a backticked token that looks like a path, constant or method
#   path        a bare path anywhere in the item
#
# Prose without a concrete citation remains for human review. This audit reports
# stale claims; it never closes backlog work by itself.

require "open3"
require "set"
require_relative "../lib/trace/dmesg"

ROOT = File.expand_path("../..", __dir__)
TODO = File.join(ROOT, "TODO.md")

TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze

PATH_LINE = %r{\b((?:MASTER|RAILS|OPENBSD|STUDIO)?/?[\w./-]+\.(?:rb|yml|yaml|scss|css|js|mjs|html|erb|md|sh|ksh|zsh|rake|json|toml|conf|zone|txt))[:#](\d+)\b}
BARE_PATH = %r{\b((?:MASTER|RAILS|OPENBSD|STUDIO)/[\w./-]+\.(?:rb|yml|yaml|scss|css|js|mjs|html|erb|md|sh|ksh|zsh|rake|json|toml|conf|zone|txt))\b}

module BacklogClaims
  module_function

  def tracked
    return @tracked if defined?(@tracked)

    output, status = Open3.capture2("git", "-C", ROOT, "ls-files")
    raise "could not inspect tracked repository paths (git ls-files failed)" unless status.success?

    @tracked = output.lines.map(&:strip).to_set
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
    return @lines[path] if @lines.key?(path)

    @lines[path] = File.foreach(File.join(ROOT, path)).count
  rescue StandardError
    nil
  end

  # Return only open checklist items, identified by their source line. The
  # checkbox, not wording inside the description, is authoritative for status.
  def parse_items(body)
    body.each_line.with_index(1).filter_map do |line, line_number|
      match = /^\s*-\s+\[ \]\s+(.+?)\s*$/.match(line)
      [line_number.to_s, match[1]] if match
    end
  end

  def items
    parse_items(File.read(TODO))
  end

  def verdict(text)
    findings = []
    cited_paths = text.scan(PATH_LINE)
    bare_paths = text.scan(BARE_PATH).flatten.uniq

    cited_paths.each do |path, line|
      resolved = resolve(path)
      if resolved.nil?
        findings << "missing path: #{path}"
        next
      end
      if resolved == :ambiguous
        findings << "inconclusive path: #{path} matches more than one tracked file"
        next
      end

      count = line_count(resolved)
      if count.nil?
        findings << "inconclusive line: could not read #{path}"
      elsif line.to_i > count
        findings << "stale line: #{path}:#{line} (file has #{count} lines)"
      end
    end

    bare_paths.each do |path|
      resolved = resolve(path)
      if resolved.nil?
        findings << "missing path: #{path}"
      elsif resolved == :ambiguous
        findings << "inconclusive path: #{path} matches more than one tracked file"
      end
    end

    return [:citation_findings, findings.uniq] unless findings.empty?
    return :citation_holds unless cited_paths.empty? && bare_paths.empty?

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
    kind = token_verdict(text)
    tally[kind] += 1
    working_set << [number, text.lines.first.strip[0, 88]] if kind == :every_name_is_ours
  end

  Master::Trace::Dmesg.attach("claims0", "master0", "#{items.size} items, #{symbols.size} identifiers indexed")
  tally.sort_by { |_, n| -n }.each { |k, n| Master::Trace::Dmesg.status("claims0", "#{k}, #{n}") }
  Master::Trace::Dmesg.status("claims0", "working set, #{working_set.size}")
  working_set.first(Integer(ENV.fetch("LIMIT", "25"))).each { |n, head| Master::Trace::Dmesg.status("claims0", "#{n}, #{head}") }
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
    by_tree[tree_of(text)] << number
  end

  total = by_tree.values.sum(&:size)
  Master::Trace::Dmesg.attach("claims0", "master0", "#{total} unchecked items, partitioned by tree")
  by_tree.sort_by { |_, v| -v.size }.each do |tree, numbers|
    Master::Trace::Dmesg.status("claims0", "#{tree}, #{numbers.size}, #{numbers.first(3).join(", ")}")
  end
  Master::Trace::Dmesg.status("claims0", "TODO.md is the shared file; spans_trees and shared need manual division")
end

  def run
    tally = Hash.new(0)
    findings = []

    items.each do |number, text|
      verdict_result = verdict(text)
      kind = verdict_result.is_a?(Array) ? verdict_result.first : verdict_result
      tally[kind] += 1
      if verdict_result.is_a?(Array)
        findings << [number, verdict_result.last, text.lines.first.strip[0, 96]]
      end
    end

    Master::Trace::Dmesg.attach("claims0", "master0", "#{items.size} unchecked checklist items")
    tally.sort_by { |_, n| -n }.each { |k, n| Master::Trace::Dmesg.status("claims0", "#{k}, #{n}") }

    return if findings.empty?

    Master::Trace::Dmesg.status("claims0", "#{findings.size} items with citation findings")
    findings.first(Integer(ENV.fetch("LIMIT", "40"))).each do |number, detail, head|
      Master::Trace::Dmesg.status("claims0", "#{number}, #{head}")
      Master::Trace::Dmesg.status("claims0", Array(detail).join("; "))
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.include?("--partition")
    BacklogClaims.partition_report
  elsif ARGV.include?("--symbols")
    BacklogClaims.symbol_report
  else
    BacklogClaims.run
  end
end
