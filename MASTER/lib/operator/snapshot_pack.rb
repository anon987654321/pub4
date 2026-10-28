# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../io/exec"
require "set"
require_relative "snapshot_map"
require_relative "snapshot_minify"
require_relative "snapshot_parts"
require_relative "snapshot_verify"

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
    INTEGRITY_PREFIX = "## END OF PACK\nsha256="
    INTEGRITY_FOOTER_BYTES = INTEGRITY_PREFIX.bytesize + 64 + 1

    # Kinds of file left out entirely: bytes that carry no reading value.
    OMIT = [
      [%r{(\A|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Gemfile\.lock|composer\.lock)\z}, "lockfile"],
      [/\.lock\z/, "lockfile"],
      [/\.min\.(js|css)\z/, "minified"],
      [/\.bundle\.js\z/, "generated bundle"],
      [%r{(\A|/)three[^/]*\.js\z}, "vendored library"],
      [%r{(\A|/)vendor/}, "vendored library"],
      [%r{(\A|/)(tmp|temp|generated|node_modules|coverage|storage|output|outputs|build|dist|renders|render|scratch|cache|three_build)/}, "generated or dependency directory"],
      [%r{(\A|/)\.(git|master|bundle|claude|idea|vscode)/}, "tool state"],
      [%r{/public/assets/|/app/assets/builds/}, "built assets"],
      [/\.map\z/, "source map"],
      [%r{/checks/data/layout_snapshots/}, "stored layout snapshots"],
      [/\.(ipynb|jsonl)\z/, "notebook or log data"],
    ].freeze

    TEST_PATH = %r{(\A|/)(test|spec)/|_test\.(rb|mjs|js)\z|\.test\.(mjs|js)\z}
    DOCUMENTS = %r{(\A|/)(CLAUDE|AGENTS|README)\.md\z|(\A|/)soul\.yml\z}
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

    def block(path, body, digest: nil)
      longest = body.scan(/^\x60{3,}/).map(&:length).max.to_i
      fence = "\x60" * [3, longest + 1].max
      out = +"### #{path}\n"
      out << "SHA-256 (normalized source): #{digest}\n" if digest
      out << "#{fence}#{FENCE_LANG.fetch(File.extname(path).downcase, '')}\n#{body.chomp}\n#{fence}\n"
      out
    end

    # The footer digest covers every byte before the END OF PACK heading.
    # A missing footer or changed byte makes the reading copy unverifiable.
    def seal_text(text)
      text + "#{INTEGRITY_PREFIX}#{Digest::SHA256.hexdigest(text)}\n"
    end

    def verify_text(text)
      match = text.match(/^## END OF PACK\nsha256=([0-9a-f]{64})\n\z/)
      return false unless match

      Digest::SHA256.hexdigest(text[0...match.begin(0)]) == match[1]
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
      paths = host.respond_to?(:all_tracked) ? host.all_tracked(tree) : host.tracked(tree)
      return paths if names.empty?

      paths.select do |path|
        relative = path.delete_prefix("#{base}/")

        names.any? { |name| relative == name || relative.start_with?("#{name}/") }
      end
    end

    # What each file is: its text, its minified text, its block, and whether it may be inlined.
    def files_for(host, paths, tests:)
      files = []
      omitted = Hash.new { |hash, key| hash[key] = [] }

      paths.each do |path|
        absolute = File.join(host::REPO, path)
        next unless File.file?(absolute) && !host.binary?(absolute)

        reason = omit_reason(path)
        next omitted[reason] << path if reason

        files << file_entry(path, absolute, tests:)
      end

      [rank_centrality(files), omitted]
    end

    def file_entry(path, absolute, tests:)
      original = File.read(absolute, encoding: "UTF-8", invalid: :replace, undef: :replace)
      minified = minify(path, original)
      rendered_source = "#{minified.chomp}\n"
      digest = Digest::SHA256.hexdigest(rendered_source)
      inlinable = minified.bytesize <= FILE_CAP && (tests || !test_path?(path))

      { path:, original:, minified:, digest:, block: block(path, minified, digest:), inlinable: }
    end

    # What one write is working on: where, what, how much room, and what came of it.
    Job = Struct.new(:host, :tree, :budget, :only, :tests, :since, :changes, :files, :omitted, :chosen, keyword_init: true)

    def header(job, sha)
      out = +"# #{job.tree} — source snapshot for another model\n\n"
      out << "Pack: tree=#{job.tree} git=#{sha} files=#{job.files.size} inlined=#{job.chosen.size} "
      out << "map_only=#{job.files.size - job.chosen.size} omitted=#{job.omitted.values.sum(&:size)} "
      out << "budget=#{job.budget}"
      if job.changes
        out << " since=#{job.changes[:resolved]} changed=#{job.changes[:current].size} "
        out << "deleted=#{job.changes[:deleted].size} renamed=#{job.changes[:renamed].size}"
      end
      out << "\n\n"
      out << explanation(job.tree)
      out << omitted_note(job.omitted)
    end

    def omitted_note(omitted)
      return "" if omitted.empty?

      "Omitted: #{omitted.sort.map { |reason, list| "#{reason} (#{list.size})" }.join(', ')}.\n\n"
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
        "For an incremental handoff, use `bin/operator snapshot #{tree} --budget=BYTES --since=REF`: the Map",
        "covers the current tree, while source budget goes to changed tracked files and deletions/renames are recorded.",
        "For the whole source use `bin/operator snapshot` with no budget.\n\n",
      ].join(" ")
    end

    # Every snapshot file the tree has at the repo root, whichever kind wrote it: the single file, the
    # numbered parts, the code variant or the byte-exact mirror's parts. The operator asked for the
    # old ones to be deleted before a new pack is written, and a pack beside the old one's extra parts
    # leaves a reader unable to tell which are current. Only files named snapshot_<TREE>*.md at the
    # repo root match.
    def clear(host, tree, io: $stdout)
      old = Dir.children(host::REPO).grep(SnapshotParts.stale_pattern(tree)).map { |name| File.join(host::REPO, name) }
      FileUtils.rm_f(old)
      Master::Trace::Dmesg.status("snapshot0", "#{tree}, removed #{old.size} old snapshot file(s)", io:)

      old
    end

    # The budgeted reading copy is one file. The full source is parts (SnapshotParts), the exact
    # variant, the code variant, or both, each verified against the tree after it is written.
    def write(host, tree, io: $stdout, **options)
      if options[:full]
        clear(host, tree, io:)
        return write_full(host, tree, io:, **options)
      end

      job = Job.new(host:, tree:, budget: options.fetch(:budget, DEFAULT_BUDGET), only: options[:only],
                    tests: options.fetch(:tests, false), since: options[:since])
      paths = paths_for(host, tree, only: job.only)
      job.changes = change_set(host, tree, job.since, only: job.only) if job.since
      if paths.empty?
        clear(host, tree, io:)
        return nothing_matched(tree, io)
      end

      # Compose and validate before removing the last good pack. A bad budget or
      # invalid input must not destroy the previous reading copy.
      text = compose(job, paths)
      raise ArgumentError, "snapshot: generated pack exceeds budget (#{text.bytesize} > #{job.budget} bytes)" if text.bytesize > job.budget

      clear(host, tree, io:)
      path = File.join(host::REPO, "snapshot_#{tree}.md")
      File.write(path, text, encoding: "UTF-8")
      report(job, path, text, io:)

      [path]
    end

    def write_full(host, tree, io:, only: nil, variants: [:exact], part_bytes: nil, **)
      paths = paths_for(host, tree, only:)
      return nothing_matched(tree, io) if paths.empty?

      size = part_bytes || ENV.fetch("MASTER_SNAPSHOT_PART_BYTES", SnapshotParts::DEFAULT_PART_BYTES).to_i
      variants.flat_map do |variant|
        written = SnapshotParts.write(host, tree, paths:, variant:, part_bytes: size, io:)
        SnapshotVerify.call(host, tree, variant:, only:, io:)
        written
      end
    end

    # The whole file: header, map, then the chosen files whole. The room for source is what the
    # budget leaves after the header and the map, which both depend on the choice by a few bytes.
    def compose(job, paths)
      sha = job.host.head_sha
      job.files, job.omitted = files_for(job.host, paths, tests: job.tests)
      job.changes ||= change_set(job.host, job.tree, job.since, only: job.only) if job.since
      job.chosen = Set.new
      selected = job.changes ? job.files.select { |file| job.changes[:current].include?(file[:path]) } : job.files
      map = lambda do |chosen|
        marker = job.changes && ->(file) { job.changes[:current].include?(file[:path]) ? "Δ" : nil }
        SnapshotMap.map_text(job.files, chosen, tag: marker)
      end
      delta = changes_note(job.changes)
      room = job.budget - header(job, sha).bytesize - delta.bytesize - map.call(job.chosen).bytesize -
        "\n## Map\n\n\n## Source\n\n".bytesize - INTEGRITY_FOOTER_BYTES - 80
      job.chosen = choose(selected, room)
      render = lambda do
        text = header(job, sha)
        text << delta
        text << "## Map\n\n#{map.call(job.chosen)}\n## Source\n\n"
        job.files.sort_by { |f| reading_order(f) }.select { |f| job.chosen.include?(f[:path]) }.each { |f| text << f[:block] << "\n" }
        seal_text(text)
      end

      text = render.call
      while text.bytesize > job.budget && !job.chosen.empty?
        least_important = selected.select { |file| job.chosen.include?(file[:path]) }.max_by { |file| reading_order(file) }
        job.chosen.delete(least_important[:path])
        text = render.call
      end

      text
    end

    # A delta retains the full current Map but spends source budget only on changed
    # tracked paths. JSON-quoted paths cannot break the report with unusual filenames.
    def change_set(host, tree, reference, only: nil)
      ref = reference.to_s
      raise ArgumentError, "snapshot: --since needs a non-option commit reference" if ref.empty? || ref.start_with?("-")

      resolved, _err, status = Master::Io::Exec.capture3("git", "rev-parse", "--verify", "--quiet", "#{ref}^{commit}", chdir: host::REPO)
      raise ArgumentError, "snapshot: --since reference #{ref.inspect} is not a commit" unless status.success?

      base = resolved.strip
      tree_path = host::TREE_PATHS.fetch(tree)
      raw, err, status = Master::Io::Exec.capture3(
        "git", "diff", "--no-ext-diff", "--no-textconv", "--name-status", "-z", "--find-renames", base, "--", tree_path,
        chdir: host::REPO,
      )
      raise ArgumentError, "snapshot: git diff failed for --since #{ref.inspect}: #{err.strip}" unless status.success?

      changed = []
      deleted = []
      renamed = []
      fields = raw.split("\0")
      index = 0
      while index < fields.length
        kind = fields[index]
        index += 1
        if kind.start_with?("R", "C")
          old_path, new_path = fields[index, 2]
          raise ArgumentError, "snapshot: malformed git diff rename record" unless old_path && new_path

          index += 2
          renamed << [old_path, new_path] if kind.start_with?("R")
          changed << new_path
        else
          path = fields[index]
          raise ArgumentError, "snapshot: malformed git diff path record for #{kind.inspect}" unless path

          index += 1
          kind == "D" ? deleted << path : changed << path
        end
      end

      result = { reference: ref, resolved: base[0, 12], current: changed.uniq, deleted: deleted.uniq, renamed: renamed.uniq }
      names = Array(only).map { |prefix| prefix.to_s.delete_prefix("#{tree_path}/").delete_suffix("/") }.reject(&:empty?)
      return result if names.empty?

      in_scope = lambda do |path|
        relative = path.delete_prefix("#{tree_path}/")
        names.any? { |name| relative == name || relative.start_with?("#{name}/") }
      end
      result.merge(
        current: result[:current].select { |path| in_scope.call(path) },
        deleted: result[:deleted].select { |path| in_scope.call(path) },
        renamed: result[:renamed].select { |old_path, new_path| in_scope.call(old_path) || in_scope.call(new_path) },
      )
    end

    def changes_note(changes)
      return "" unless changes

      out = +"## Changes since #{JSON.generate(changes[:reference])}\n\n"
      out << "The Map covers the current tree; source budget is reserved for changed tracked paths. "
      out << "Deleted=#{changes[:deleted].size}; renamed=#{changes[:renamed].size}.\n\n"
      shown = 0
      changes[:deleted].first(40).each do |path|
        out << "- deleted: #{JSON.generate(path)}\n"
        shown += 1
      end
      changes[:renamed].first([40 - shown, 0].max).each do |old_path, new_path|
        out << "- renamed: #{JSON.generate(old_path)} -> #{JSON.generate(new_path)}\n"
        shown += 1
      end
      total = changes[:deleted].size + changes[:renamed].size
      out << "- #{total - shown} additional deletion/rename record(s) not expanded\n" if total > shown
      out << "\n"
      out
    end

    def nothing_matched(tree, io)
      Master::Trace::Dmesg.status("snapshot0", "#{tree}, nothing matched, skipped", io:)

      []
    end

    # write raises before this on a pack over its budget, so the line reports size alone.
    def report(job, path, text, io:)
      Master::Trace::Dmesg.status(
        "snapshot0",
        "#{job.tree}, #{File.basename(path)}, #{text.bytesize} bytes (~#{text.bytesize / 4000}K tokens), " \
        "inlined #{job.chosen.size} of #{job.files.size} files",
        io:,
      )
    end
  end
end
