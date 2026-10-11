# frozen_string_literal: true

require "fileutils"
require "set"
require_relative "snapshot_map"
require_relative "snapshot_minify"

module Operator

  # A reading copy of a tree for another model.
  #
  # The mirror in tools/snapshot.rb is byte-exact so that it can be rehydrated, and it runs to
  # 26 MB across the four trees. A GLM or DeepSeek context holds about half a megabyte of text,
  # so the mirror cannot be shared with them at all. This copy gives up exactness for size and
  # writes one file a tree: a map of every file, then as much of the most important source as the
  # budget holds. What each format loses is in SnapshotMinify.
  module SnapshotPack
    # About 95K tokens: what a 128K-context model can take with room left to answer.
    DEFAULT_BUDGET = 380_000
    # A file larger than this after minifying is described in the map and never inlined.
    FILE_CAP = 60_000

    # Kinds of file left out entirely: bytes that carry no reading value.
    OMIT = [
      [%r{(\A|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Gemfile\.lock|composer\.lock)\z}, "lockfile"],
      [/\.lock\z/, "lockfile"],
      [/\.min\.(js|css)\z/, "minified"],
      [/\.bundle\.js\z/, "generated bundle"],
      [%r{(\A|/)three[^/]*\.js\z}, "vendored library"],
      [%r{(\A|/)vendor/}, "vendored library"],
      [/\.map\z/, "source map"],
      [%r{/gates/data/layout_snapshots/}, "stored layout snapshots"],
      [%r{/dilla/project/}, "session state"],
      [/\.(ipynb|jsonl)\z/, "notebook or log data"],
    ].freeze

    TEST_PATH = %r{(\A|/)(test|spec)/|_test\.(rb|mjs|js)\z|\.test\.(mjs|js)\z}
    DOCUMENTS = %r{(\A|/)(CLAUDE|AGENTS|README|ARCHITECTURE)\.md\z|(\A|/)soul\.yml\z}
    FENCE_LANG = {
      ".rb" => "ruby", ".rake" => "ruby", ".yml" => "yaml", ".yaml" => "yaml", ".json" => "json",
      ".js" => "javascript", ".mjs" => "javascript", ".ts" => "typescript", ".css" => "css",
      ".scss" => "scss", ".html" => "html", ".erb" => "erb", ".md" => "markdown",
      ".sh" => "zsh", ".zsh" => "zsh", ".ksh" => "zsh"
    }.freeze

    module_function

    def omit_reason(path) = OMIT.find { |pattern, _| path.match?(pattern) }&.last

    def test_path?(path) = path.match?(TEST_PATH)

    def minify(path, text) = SnapshotMinify.call(path, text)

    def block(path, body)
      longest = body.scan(/^`{3,}/).map(&:length).max.to_i
      fence = "`" * [3, longest + 1].max

      "### #{path}\n#{fence}#{FENCE_LANG.fetch(File.extname(path).downcase, '')}\n#{body.chomp}\n#{fence}\n"
    end

    # Lower is read first: the documents that say what the tree is, then the entry points, then
    # the top of lib, and tests last because a test is evidence about code, not the code.
    def priority(path)
      return 0 if path.match?(DOCUMENTS)
      return 1 if path.match?(%r{\A[^/]+/bin/})
      return 2 if path.match?(%r{\A[^/]+/lib/[^/]+\.rb\z})
      return 9 if test_path?(path)

      5
    end

    def reading_order(file)
      [priority(file[:path]), -file[:centrality].to_i, file[:path].count("/"), file[:block].bytesize]
    end

    # Which files are inlined: the priority order, then the file more of the others mention, then
    # the shallower path, then the smaller file, each one whole, until the room is spent. A file over
    # FILE_CAP, or a test, is never inlined.
    def choose(files, room)
      chosen = Set.new

      files.sort_by { |f| reading_order(f) }.each do |f|
        next unless f[:inlinable]
        next if f[:block].bytesize > room

        chosen << f[:path]
        room -= f[:block].bytesize
      end

      chosen
    end

    # How many other files mention each file's main constant (fix_loop.rb names FixLoop): a hub is
    # read before a leaf. One pass over the text, a constant counted once a file.
    def rank_centrality(files)
      mentions = Hash.new(0)
      files.each { |f| f[:minified].scan(/\b[A-Z][A-Za-z0-9]{2,}\b/).uniq.each { |name| mentions[name] += 1 } }

      files.each do |f|
        name = File.basename(f[:path], ".*").split(/[_\-.]/).map(&:capitalize).join
        own = f[:minified].match?(/\b#{Regexp.escape(name)}\b/) ? 1 : 0
        f[:centrality] = f[:path].end_with?(".rb") ? mentions[name] - own : 0
      end
    end

    def paths_for(host, tree, only:)
      base = host::TREE_PATHS.fetch(tree)
      names = Array(only).map { |prefix| prefix.to_s.delete_prefix("#{base}/").delete_suffix("/") }.reject(&:empty?)
      paths = host.tracked(tree)
      return paths if names.empty?

      paths.select do |path|
        relative = path.delete_prefix("#{base}/")

        names.any? { |name| relative == name || relative.start_with?("#{name}/") }
      end
    end

    # What each file is: its text, its minified text, its block, and whether it may be inlined.
    def files_for(host, paths, tests:, full: false)
      files = []
      omitted = Hash.new { |hash, key| hash[key] = [] }

      paths.each do |path|
        absolute = File.join(host::REPO, path)
        next unless File.file?(absolute) && !host.binary?(absolute)

        reason = omit_reason(path)
        next omitted[reason] << path if reason

        files << file_entry(path, absolute, tests:, full:)
      end

      [rank_centrality(files), omitted]
    end

    def file_entry(path, absolute, tests:, full: false)
      original = File.read(absolute, encoding: "UTF-8", invalid: :replace, undef: :replace)
      minified = full ? original : minify(path, original)
      inlinable = full || (minified.bytesize <= FILE_CAP && (tests || !test_path?(path)))

      { path:, original:, minified:, block: block(path, minified), inlinable: }
    end

    # What one write is working on: where, what, how much room, and what came of it.
    Job = Struct.new(:host, :tree, :budget, :only, :tests, :full, :files, :omitted, :chosen, keyword_init: true)

    def header(job, sha)
      out = +"# #{job.tree} — source snapshot for another model\n\n"
      out << "Pack: tree=#{job.tree} git=#{sha} files=#{job.files.size} inlined=#{job.chosen.size} "
      out << "map_only=#{job.files.size - job.chosen.size} omitted=#{job.omitted.values.sum(&:size)} "
      out << "budget=#{job.full ? 'full' : job.budget}\n\n"
      out << (job.full ? full_explanation : explanation(job.tree))
      out << omitted_note(job.omitted)
    end

    def omitted_note(omitted)
      return "" if omitted.empty?

      "Omitted: #{omitted.sort.map { |reason, list| "#{reason} (#{list.size})" }.join(', ')}.\n\n"
    end

    def full_explanation
      [
        "The full source: every tracked text file of the tree, byte for byte, tests included.",
        "**Map** lists every file: name [lines] — purpose | what it declares. **Source** holds each file whole,",
        "in reading order (the constitution and entry points first, tests last). Only files with no reading",
        "value are left out, and the Omitted line names them. For a smaller reading copy use",
        "`bin/operator snapshot --budget=BYTES`.\n\n",
      ].join(" ")
    end

    def explanation(tree)
      ask = "bin/operator snapshot #{tree} --only=<dir or file>"
      [
        "One file, sized for a model's context. **Map** lists every file: name [lines] — purpose | what it declares.",
        "**Source** holds the most important files whole, in priority order (the constitution and entry points",
        "first, then the files others mention, smaller before larger, tests last) until the budget is spent.",
        "A `~` marks a file described in the map only; ask for it with",
        "`#{ask}`, which spends the whole budget on that scope.",
        "It is a reading copy, not a mirror: comments and blank lines are removed (a file's first comment stays",
        "as one line), JSON is compacted, and Ruby is changed only by removing comments and blank lines.",
        "For exact bytes use `bin/operator snapshot --mirror`.\n\n",
      ].join(" ")
    end

    # Every snapshot file the tree has at the repo root, whichever kind wrote it: the single file or the
    # byte-exact mirror's parts. The operator asked for the old ones to be deleted before
    # a new pack is written, and a pack beside the old one's extra parts leaves a reader unable to
    # tell which are current. Only files named snapshot_<TREE>*.md at the repo root match.
    def clear(host, tree, io: $stdout)
      pattern = /\Asnapshot_#{Regexp.escape(tree)}(\.part\d+)?\.md\z/
      old = Dir.children(host::REPO).grep(pattern).map { |name| File.join(host::REPO, name) }
      FileUtils.rm_f(old)
      Master::Trace::Dmesg.status("snapshot0", "#{tree}, removed #{old.size} old snapshot file(s)", io:)

      old
    end

    def write(host, tree, io: $stdout, **options)
      clear(host, tree, io:)
      job = Job.new(host:, tree:, budget: options.fetch(:budget, DEFAULT_BUDGET), only: options[:only],
                    tests: options.fetch(:tests, false), full: options.fetch(:full, false))
      paths = paths_for(host, tree, only: job.only)
      return nothing_matched(tree, io) if paths.empty?

      text = compose(job, paths)
      path = File.join(host::REPO, "snapshot_#{tree}.md")
      File.write(path, text, encoding: "UTF-8")
      report(job, path, text, io:)

      [path]
    end

    # The whole file: header, map, then the chosen files whole. The room for source is what the
    # budget leaves after the header and the map, which both depend on the choice by a few bytes.
    def compose(job, paths)
      sha = job.host.head_sha
      job.files, job.omitted = files_for(job.host, paths, tests: job.tests, full: job.full)
      job.chosen = Set.new
      room = job.full ? Float::INFINITY : job.budget - header(job, sha).bytesize - SnapshotMap.map_text(job.files, job.chosen).bytesize - 40
      job.chosen = choose(job.files, room)
      text = header(job, sha)
      text << "## Map\n\n#{SnapshotMap.map_text(job.files, job.chosen)}\n## Source\n\n"
      job.files.sort_by { |f| reading_order(f) }.select { |f| job.chosen.include?(f[:path]) }.each { |f| text << f[:block] << "\n" }

      text
    end

    def nothing_matched(tree, io)
      Master::Trace::Dmesg.status("snapshot0", "#{tree}, nothing matched, skipped", io:)

      []
    end

    def report(job, path, text, io:)
      over = !job.full && text.bytesize > job.budget ? " — OVER the budget: the map is too large, narrow with --only" : ""
      Master::Trace::Dmesg.status(
        "snapshot0",
        "#{job.tree}, #{File.basename(path)}, #{text.bytesize} bytes (~#{text.bytesize / 4000}K tokens), " \
        "inlined #{job.chosen.size} of #{job.files.size} files#{over}",
        io:,
      )
    end
  end
end
