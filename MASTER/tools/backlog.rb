# frozen_string_literal: true

require "digest"
require_relative "backlog_classify"
require_relative "backlog_reader"
require_relative "backlog_store"

# The backlog generator: one YAML row per checkbox item in the root TODO.md.
#
# TODO.md is prose that a session reads, and /fix's work intake wants rows it
# can rank, gate and receipt. Hand-copying the items into a second file
# re-creates the staleness problem that file warns about — an entry outliving
# its source — so the rows are generated, TODO.md stays the one source, and
# the store's --check fails when the generated file no longer matches it.
#
# id, text and section are mechanical extractions. tree, kind and size are
# derived heuristics from the item's own words: a starting classification, and
# a deliberate curation of their rules belongs in Backlog::Classify, not in
# the output file. done_when carries the first runnable command the item
# names, verbatim; an item that names none carries the reason instead. A row
# whose checkbox is checked off is landed evidence and leaves the backlog in
# the same read.
module Backlog
  MASTER_ROOT = File.expand_path("..", __dir__)
  SOURCE = File.expand_path("../TODO.md", MASTER_ROOT)
  DEST = File.join(MASTER_ROOT, "data", "backlog.yml")

  TREES = %w[MASTER RAILS OPENBSD STUDIO cross operator].freeze
  KINDS = %w[verify mechanical design product operator-only plan].freeze
  SIZES = %w[s m l].freeze

  ROOTED_PATH = %r{(?:MASTER|RAILS|OPENBSD|STUDIO|pub4)/[\w.\-]+(?:/[\w.\-]+)*}
  REL_PATH = %r{
    (?<![\w/])(?:lib|bin|data|docs|tools|checks|test|law|man|contracts|
    plugins|app|config|knowledge|public|storage|etc|usr|home|var|dev|db|
    script)/[\w.\-]+(?:/[\w.\-]+)*
  }x
  FILE_PATH = /\b[\w\-]+\.(?:yml|yaml|rb|md|json|erb|scss|js|mjs|png|conf|lock|csv|webp|wav)\b/

  module_function

  def generate(source: SOURCE)
    entries = parse(source).map { |item| entry(item) }
    raise "no checkbox items found in #{source}: a parse that reads nothing says nothing" if entries.empty?

    assign_ids!(entries)
  end

  def parse(source)
    raise "missing source #{source}" unless File.file?(source)

    reader = Reader.new
    File.foreach(source) { |raw| reader.read(raw.chomp) }
    reader.finish
  end

  def entry(item)
    text = item[:prose].join(" ")
    section = section_of(item)
    kind = Classify.kind(item:, text:, section:)
    command = first_command(item)

    {
      id: nil,
      text:,
      section:,

      tree: owner(item:, text:, section:, kind:),
      kind:,
      size: size_of(text),
      scope_paths: scope_paths(text),

      done_when: command,
      done_when_note: note_for(item:, command:, kind:),
    }
  end

  def section_of(item)
    # A row above any ## heading takes the document title as its section.
    [item[:h2] || item[:h1], item[:h3]].compact.join(" — ")
  end

  # The tree is the tree the text speaks for; a tie or a plan speaks for all.
  def owner(item:, text:, section:, kind:)
    return "operator" if kind == "operator-only"
    return "cross" if item[:plan]

    counts = Classify.signal_counts(text, section)
    top = counts.values.max
    return "cross" if top.nil? || top.zero?

    leaders = counts.select { |signal, total| total == top }.keys
    leaders.size == 1 ? leaders.first : "cross"
  end

  def size_of(text)
    return "l" if text.length > 700
    return "m" if text.length > 200

    "s"
  end

  def scope_paths(text)
    paths = text.scan(ROOTED_PATH) + text.scan(REL_PATH) + text.scan(FILE_PATH)
    paths.map(&:strip).uniq.sort
  end

  # The first runnable command the item names, verbatim: prose backticks
  # first, then the item's fenced code, one command per fence line. A span
  # counts when the prose asks for a command run, or when the span is itself a
  # full invocation on a named checkout ("cd RAILS/bsdports && bin/ci").
  def first_command(item)
    spans = item[:prose].flat_map { |line| line.scan(/`([^`\n]+)`/).flatten }
    spans += item[:code].reject(&:empty?)
    hint = item[:prose].join(" ").match?(Store::EXEC_HINT)
    spans.find { |span| runnable?(span) && (hint || span.match?(/\Acd\s/)) }
  end

  def runnable?(span)
    stripped, chained = without_invocation_prefix(span)
    words = stripped.split
    return false if words.empty?
    return true if command_words?(words, stripped)

    tool_ref?(words.first) && (words.size >= 2 || chained)
  end

  def command_words?(words, stripped)
    words.first.match?(%r{\A(?:ruby|rake|bundle|node|pfctl|swapctl|ssh|git)\z}) &&
      (words.size >= 2 || stripped.include?(":"))
  end

  def tool_ref?(word)
    word.start_with?("bin/", "./") || word.match?(%r{\A(?:MASTER|OPENBSD)/bin/})
  end

  def without_invocation_prefix(span)
    stripped = span.sub(/\A\$/, "")
    # A cd or environment prefix makes the span an invocation written for a
    # checkout, so a bare "bin/ci" inside it is a command, not a named path.
    chained = span.match?(%r{\A(?:cd\s|[A-Z_][A-Z0-9_]*=)})
    loop do
      candidate = stripped.sub(%r{\A(?:cd\s+\S+\s*&&\s+|[A-Z_][A-Z0-9_]*=(?:"[^"]*"|\S+)\s+)}, "")
      return [stripped, chained] if candidate == stripped

      chained = true
      stripped = candidate
    end
  end

  def note_for(item:, command:, kind:)
    return if command
    return "pub5 is gated on the operator's freeze condition, not on one command" if item[:plan]
    return "operator-owned action; the acceptance is the operator's decision" if kind == "operator-only"

    "no runnable command named in the item text"
  end

  def assign_ids!(entries)
    used = {}
    entries.each { |row| row[:id] = slug_for(row[:text], used) }
    entries
  end

  def slug_for(text, used)
    base = text.downcase.scan(/[a-z0-9]+/).first(8).join("-")[0, 80]
    base = "item" if base.empty?
    return base unless used.key?(base)

    digest = Digest::SHA1.hexdigest(text)[0, 6]
    serial = 1
    loop do
      candidate = "#{base}-#{digest}#{serial > 1 ? "-#{serial}" : ""}"
      return candidate unless used.key?(candidate)

      serial += 1
    end
  end
end

if $PROGRAM_NAME == __FILE__
  run = Backlog::Store.parse_cli(ARGV)
  if run[:check]
    exit(Backlog::Store.check(source: run[:source], out: run[:out]))
  else
    exit(Backlog::Store.write(source: run[:source], out: run[:out], refresh: run[:refresh]))
  end
end
