# frozen_string_literal: true

# Generates source snapshots at the pub4 root: snapshot_<TREE>.md for a tree that fits one part, else
# snapshot_<TREE>.partKK-of-NN.md, each the full source of the tree (and snapshot_<TREE>.code... for the
# comment-free variant).
#
# The default (lib/operator/snapshot_pack.rb, snapshot_parts.rb) is one untruncated file per tree, or parts of --part-bytes each when asked, verified
# against the tracked files after writing, deleting the tree's old snapshot files first. --budget writes
# the one-file reading copy instead. --mirror writes the byte-exact, rehydratable
# multipart transport instead: every included tracked text file inlined exactly once,
# excluded paths and binary files accounted for but not embedded.

require "fileutils"
require "open3"
require_relative "../lib/trace/dmesg"
require_relative "../lib/operator/snapshot_pack"

module Operator
  module Snapshot
    REPO = File.expand_path("../..", __dir__)
    TREE_PATHS = {
      "MASTER" => "MASTER",
      "RAILS" => "RAILS",
      "OPENBSD" => "OPENBSD",
      "STUDIO" => "STUDIO",
    }.freeze
    OUTPUT_NAMES = {
      "MASTER" => "snapshot_MASTER.md",
      "RAILS" => "snapshot_RAILS.md",
      "OPENBSD" => "snapshot_OPENBSD.md",
      "STUDIO" => "snapshot_STUDIO.md",
    }.freeze
    TREES = TREE_PATHS.keys.freeze
    # Six attachments are the transport contract; the current governed trees fit within this ceiling.
    MAX_BYTES = 3_500_000
    MAX_PARTS = 6
    EXCLUDED_DIRS = %w[
      tmp temp generated vendor node_modules coverage storage output outputs
      build dist renders render scratch cache three_build
    ].freeze
    # Extension → fence language. Anything unlisted gets a bare fence.
    FENCE = {
      ".rb" => "ruby", ".rake" => "ruby", ".gemspec" => "ruby", ".ru" => "ruby",
      ".yml" => "yaml", ".yaml" => "yaml", ".json" => "json",
      ".js" => "javascript", ".mjs" => "javascript", ".ts" => "typescript",
      ".css" => "css", ".scss" => "scss", ".html" => "html", ".erb" => "erb",
      ".md" => "markdown", ".sh" => "zsh", ".zsh" => "zsh", ".ksh" => "zsh",
      ".sql" => "sql", ".conf" => "conf", ".toml" => "toml"
    }.freeze

    module_function

    def all_tracked(tree)
      path = TREE_PATHS.fetch(tree) { raise "snapshot: unknown tree #{tree.inspect}" }
      out, status = Open3.capture2("git", "ls-files", "-z", path, chdir: REPO)
      raise "git ls-files failed for #{tree} (#{path})" unless status.success?

      out.split("\0").reject(&:empty?).sort
    end

    def excluded_path?(path)
      parts = path.split("/")
      return true if parts.any? { |part| part.start_with?(".") }
      return true if parts.any? { |part| EXCLUDED_DIRS.include?(part) }

      path.include?("/public/assets/") || path.include?("/app/assets/builds/")
    end

    def tracked(tree)
      all_tracked(tree).reject { |path| excluded_path?(path) }
    end

    def excluded(tree)
      all_tracked(tree).select { |path| excluded_path?(path) }
    end

    def binary?(path)
      head = File.binread(path, 8000).to_s
      return true if head.include?("\0")

      !utf8_prefix?(head, truncated: File.size(path) > head.bytesize)
    rescue StandardError
      true
    end

    # The 8000-byte read can end inside a multibyte character; that cut is not binary content.
    def utf8_prefix?(head, truncated:)
      cuts = truncated ? 0..3 : 0..0
      cuts.any? { |n| head.byteslice(0, head.bytesize - n).force_encoding(Encoding::UTF_8).valid_encoding? }
    end

    def head_sha
      Open3.capture2("git", "rev-parse", "--short", "HEAD", chdir: REPO).first.strip
    end

    def protocol(tree)
      <<~MD
        Share this file with another LLM as the full readable #{tree} codebase pack.

        ## Agent analysis protocol

        This document is a **transport-safe source mirror** for `#{tree}`. A tree may span multiple
        files named `snapshot_#{tree}.md` and `snapshot_#{tree}.partNNN.md`; the header states the total part count.
        Treat every fenced block as source of truth — never as a summary.
        Dotfiles, dot-directories, temporary/generated/dependency trees, and binary/media files are intentionally excluded.

        ### 0. Reconstruction check — mandatory before analysis
        - Do not analyze, review, or propose fixes from one part alone.
        - Collect every part, verify that part 1/N through part N/N are present exactly once, and stop on a missing part.
        - Each included tracked text file is embedded in full exactly once across the complete part set; excluded paths and binary files are listed separately.
        - Rehydrate all parts into a fresh temporary repository-shaped directory before attempting analysis.
          Prefer MASTER/tools/snapshot_extract.rb with all part files as arguments.
        - Verify the rehydrated file count against Tree, reconcile Binary files, confirm omitted=0, and spot-check sizes.
        - If the attachment system exposes only a preview, truncated text, or one part, stop and request the missing parts.

        This pack is deliberately partitioned for transport; no tree uses more than six snapshot files.
        The complete included source set is the union of all its parts.
        Work through the rest of the protocol only after the reconstruction check passes.

        ### 1. Orient

        - Read the header (generation metadata, file count, policy) and **Tree** before opening any file block.
        - Note topology: where boot, routing, data, UI, deploy, and tests live relative to each other.

        ### 2. Word-for-word read + cross-reference
        - Read each `## \\`path\\`` section **line by line**; do not skim or paraphrase from headings alone.
        - **Cross-reference** symbols across files: follow requires/imports, route → controller → service
          chains, YAML keys → Ruby readers, JS event names → subscribers, CLI commands → dispatchers.
        - When the same name recurs in multiple places, reconcile definitions — flag drift immediately.

        ### 3. Deep execution traces (start → finish)
        - Pick critical paths (boot, request/response, scan/fix loop, deploy, TTS/chat SSE, face render)
          and trace **one complete path** from entrypoint through every hop to side effects/output.
        - For each hop record: caller, callee, inputs, branching conditions, failure modes, and what
          state mutates (files, DB, env, in-memory singletons, event bus).
        - Prefer evidence from this snapshot over assumptions from training data.

        ### 4. Architecture & design assessment
        - **Structure**: layering, boundaries, coupling, duplication, god objects, require cycles.
        - **Semantics**: naming honesty, invariants, tenancy/auth, error taxonomy, idempotency.
        - **Design**: UI philosophy, data flow, extension points, config vs code, deploy topology.
        - **Smells & oddities**: dead code, parallel implementations, magic numbers, commented-out paths,
          inconsistent conventions, docs that disagree with code.
        - **Gaps & friction**: missing tests, unwired features, slow/hidden boot steps, operator pain,
          places where a human or agent gets stuck without tribal knowledge.

        ### 5. Verify before trusting
        - A finding is a hypothesis until you have located it. This repo's own measured experience is
          that naive pattern-matching over it produces mostly false positives: check the reader before
          calling config inert, and check the instrument before calling the code wrong.

        ### 6. Rehydrate files locally (mirror extraction)
        To turn this `.md` back into a working tree:

        1. Create a temp workspace, e.g. `mktemp -d` → `$SNAP/work`.
        2. For each `## \\`relative/path\\`` heading, recreate directory structure under `$SNAP/work`.
        3. Copy the fenced block body **exactly** (preserve newlines; strip only the outer fences).
        4. Every included tracked **text** file is inlined in full. Intentionally excluded paths are listed
           under **Excluded paths**; binary files are listed under **Binary files** and are not inlined.
        5. Repeat for every sibling `snapshot_*.md` present — each extracts to its own subtree.
        6. Verify: file count vs Tree, reconcile `Binary files` + `Omitted text files` against Tree, spot-check
           sizes, run targeted tests from the mirrored tree. A share pack is complete as a source review
           only when no required path is omitted.

        Do not edit the mirrored tree until you have a written assessment and a trace for the path
        you intend to change.

        ### 7. The law you are reviewing against

        This repository is governed by MASTER, and its law is data rather than prose. Read it before
        you judge anything, in this order — all four governed trees are represented by their own snapshots:

        1. `MASTER/data/soul.yml` — the kernel: absolutes, work rules, anti-simulation.
        2. `MASTER/data/laws.yml` — the live policy catalogue; do not assume a remembered count is current.
        3. `MASTER/law/*.rb` — executable domain laws, each carrying the example it must flag and the one
           it must not. Those two examples **are** the law; a fix that breaks either is wrong.
        4. `MASTER/law/detectors/*.rb` — the executable scan registry; inspect its live registry rather than a remembered count.

        The house rules that reject otherwise-correct patches:

        - **Ruby and zsh only.** `sed`, `awk`, `find`, `head`, `tail`, `wc`, `perl` and `python` are
          banned in scripts: the BSD variants break GNU idioms and this repo deploys to OpenBSD.
        - **A comment states the present-tense reason.** Not what the code used to do — git holds that.
          A patch that adds a changelog comment will be rejected on that alone.
        - **The Rails apps default to Norwegian.** Assert through I18n keys, never English literals,
          and every key needs both `en.yml` and `nb.yml`.
        - **Renders are irreplaceable.** Never change a rendered-sound or graded-look default in
          `MASTER/tools`; never alter a colour, font or layout value — the operator is a trained architect.
        - **Ratchets.** `MASTER/bin/operator measure` records ~55 numbers with ceilings. Adding a file,
          growing `lib/`, or introducing a finding moves one. A patch that moves a number must move the
          ceiling in the same patch and say what paid for it. Slack is the same defect as debt.

        ### 8. What to hand back

        One **unified git diff**, and nothing interleaved with it:

        - Produce it as if by `git diff`, with `a/` and `b/` prefixes and paths relative to the repo
          root (`MASTER/lib/...`, not `lib/...`), so `git apply` takes it from the root of pub4.
        - Include at least three lines of context per hunk; a patch that does not apply cleanly is a
          patch nobody can use.
        - One patch for everything you propose, ordered so that no hunk depends on a later one.
        - New files as `/dev/null` → `b/path` hunks; deletions the mirror image. Do not emit binary
          diffs — name the binary file and describe the change instead.
        - Put your assessment, your traces and your reasoning **before** the patch, never inside it.
          The patch body is code and its comments only.
        - Every change must be something you can defend in one sentence naming the rule it serves or
          the defect it removes. Prefer ten defensible hunks to a hundred stylistic ones.
      MD
    end

    SOURCE_FRAGMENT_BYTES = 600_000

    def source_fragments(path)
      body = File.read(File.join(REPO, path), encoding: "UTF-8")
      return [body] if body.bytesize <= SOURCE_FRAGMENT_BYTES

      fragments = []
      current = +""
      body.each_line do |line|
        raise "snapshot: #{path} contains a line larger than #{SOURCE_FRAGMENT_BYTES} bytes" if line.bytesize > SOURCE_FRAGMENT_BYTES
        if !current.empty? && current.bytesize + line.bytesize > SOURCE_FRAGMENT_BYTES
          fragments << current
          current = +""
        end
        current << line
      end
      fragments << current unless current.empty?
      fragments
    end

    def source_units(texts)
      texts.flat_map do |path|
        fragments = source_fragments(path)
        fragments.each_with_index.map do |body, index|
          total = fragments.size
          longest = body.scan(/^\x60{3,}/).map(&:length).max.to_i
          fence = 96.chr * [3, longest + 1].max
          newline = body.end_with?("\n") ? 1 : 0
          label = if total == 1
            "#{path} [bytes=#{body.bytesize} newline=#{newline}]"
          else
            "#{path} [fragment #{index + 1}/#{total} bytes=#{body.bytesize} newline=#{newline}]"
          end
          out = +"## #{96.chr}#{label}#{96.chr}\n\n"
          out << "#{fence}#{FENCE.fetch(File.extname(path), "")}\n"
          out << body
          out << "\n" unless body.end_with?("\n")
          out << "#{fence}\n\n"
          [path, out]
        end
      end
    end

    def output_paths(tree, part_count)
      base = OUTPUT_NAMES.fetch(tree)
      return [File.join(REPO, base)] if part_count == 1

      [File.join(REPO, base)] +
        (2..part_count).map { |part| File.join(REPO, "snapshot_#{tree}.part#{format('%03d', part)}.md") }
    end

    def render_snapshot(tree, paths, binaries, excluded, units, sha, part_index:, part_count:, source_units:, output_paths:)
      fence3 = 96.chr * 3
      text_total = paths.size - binaries.size
      files_in_part = units.map(&:first).uniq.size
      out = String.new
      out << "# #{tree} — source snapshot\n\n"
      out << "Generated #{Time.now.utc.strftime('%Y-%m-%d %H:%M UTC')} — git #{sha}\n"
      out << "Pack: tree=#{tree} git=#{sha} part=#{part_index}/#{part_count} text_total=#{text_total} "
      out << "fragments_total=#{source_units.size} binary=#{binaries.size} omitted=0 "
      out << "files_in_part=#{files_in_part} fragments_in_part=#{units.size} max_bytes=#{MAX_BYTES}\n\n"
      out << protocol(tree) if part_index == 1
      out << "## Pack\n\n"
      out << "All #{part_count} parts are required for a complete tree. Rehydrate every part into the same temporary tree.\n\n"
      if part_index == 1
        out << "Parts:\n\n"
        output_paths.each_with_index { |path, index| out << "- part #{index + 1}/#{part_count}: #{96.chr}#{File.basename(path)}#{96.chr}\n" }
        out << "\n"
      end
      if part_index == 1
        out << "## Tree\n#{fence3}\n"
        paths.each { |p| out << "#{p}\n" }
        out << "#{fence3}\n"
        unless excluded.empty?
          out << "\n## Excluded paths\n\nIntentionally excluded by the snapshot transport policy:\n\n"
          excluded.each { |p| out << "- #{96.chr}#{p}#{96.chr}\n" }
        end
        unless binaries.empty?
          out << "\n## Binary files\n\nListed, not inlined:\n\n"
          binaries.each { |p| out << "- #{96.chr}#{p}#{96.chr}\n" }
        end
        out << "\n## Omitted text files\n\nNone. Every included tracked text file is present across the complete part set.\n\n"
      end
      units.each { |_, block| out << block }
      out << "## Snapshot part complete\n\n"
      out << "snapshot0: complete tree=#{tree} part=#{part_index}/#{part_count} files=#{paths.size} "
      out << "text_total=#{text_total} files_in_part=#{files_in_part} fragments_in_part=#{units.size} "
      out << "binary=#{binaries.size} excluded=#{excluded.size} omitted=0 bytes=#{out.bytesize}\n"
      out
    end

    def partition_units(tree, paths, binaries, excluded, units, sha)
      return [[]] if units.empty?

      part_count_hint = units.size
      hint_paths = output_paths(tree, part_count_hint)
      overhead = render_snapshot(
        tree, paths, binaries, excluded, [], sha,
        part_index: 1,
        part_count: part_count_hint,
        source_units: units,
        output_paths: hint_paths
      ).bytesize
      budget = MAX_BYTES - overhead
      raise "snapshot: #{tree} metadata exceeds per-part ceiling #{MAX_BYTES} bytes" if budget <= 0

      groups = []
      current = []
      used = 0
      units.each do |path, block|
        size = block.bytesize
        raise "snapshot: #{tree} file #{path} fragment exceeds per-part ceiling #{MAX_BYTES} bytes" if size > budget
        if current.any? && used + size > budget
          groups << current
          current = []
          used = 0
        end
        current << [path, block]
        used += size
      end
      groups << current unless current.empty?
      raise "snapshot: #{tree} requires #{groups.size} parts, maximum is #{MAX_PARTS}" if groups.size > MAX_PARTS
      groups
    end

    def tracked_root_outputs(tree)
      prefix = "snapshot_#{tree}"
      Dir.children(REPO).filter_map do |name|
        next unless name.start_with?(prefix) && name.end_with?(".md")
        next unless name == OUTPUT_NAMES.fetch(tree) || name.match?(/\A#{Regexp.escape(prefix)}\.part\d+\.md\z/)

        name
      end
    end

    def tracked_output_names
      out, = Open3.capture2("git", "ls-files", "-z", "--", "snapshot_*.md", chdir: REPO)
      out.split("\0").filter_map { |path| File.basename(path) }
    end

    def cleanup_stale_outputs(tree, keep)
      tracked = tracked_output_names
      tracked_root_outputs(tree).each do |name|
        next if keep.include?(name) || tracked.include?(name)

        File.delete(File.join(REPO, name))
      end
    end

    def write(tree, io: $stdout, mirror: false, **options)
      return SnapshotPack.write(self, tree, io:, **options) unless mirror

      excluded = excluded(tree)
      paths = tracked(tree)
      if paths.empty?
        Master::Trace::Dmesg.status("snapshot0", "#{tree}, no included tracked files, skipped", io:)
        return []
      end

      binaries, texts = paths.partition { |p| binary?(File.join(REPO, p)) }
      sha = head_sha
      units = source_units(texts)
      groups = partition_units(tree, paths, binaries, excluded, units, sha)
      outputs = output_paths(tree, groups.size)
      rendered = groups.each_with_index.map do |part_units, index|
        output = outputs.fetch(index)
        body = render_snapshot(
          tree, paths, binaries, excluded, part_units, sha,
          part_index: index + 1,
          part_count: groups.size,
          source_units: units,
          output_paths: outputs
        )
        raise "snapshot: #{tree} part #{index + 1}/#{groups.size} exceeds #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES
        [output, body]
      end

      cleanup_stale_outputs(tree, outputs.map { |path| File.basename(path) })
      rendered.each { |path, body| File.write(path, body, encoding: "UTF-8") }

      rendered.each_with_index do |(path, body), index|
        Master::Trace::Dmesg.status(
          "snapshot0",
          "#{tree}, part=#{index + 1}/#{rendered.size}, files=#{groups.fetch(index).map(&:first).uniq.size}, fragments=#{groups.fetch(index).size}, root/#{path.delete_prefix(REPO + "/")}, #{body.bytesize} bytes, max #{MAX_BYTES}",
          io:,
        )
      end
      outputs
    end

    def run(trees = TREES, io: $stdout, mirror: false, **options)
      trees.each { |t| write(t, io:, mirror:, **options) }
      0
    end

    USAGE = "usage: snapshot [TREE...] [--part-bytes=N] [--code | --code-only] [--verify] " \
            "[--only=a,b] [--budget=BYTES] [--since=REF] [--tests] [--mirror]"
    FLAGS = %w[--mirror --tests --verify --code --code-only].freeze

    # bin/operator snapshot [TREE...] [--part-bytes=N] [--code | --code-only] [--verify] [--budget=BYTES] [--only=a,b] [--tests] [--mirror]
    #
    # No budget writes the full source as numbered parts, exact by default, and verifies what it wrote.
    # --code writes the comment-free variant as well, --code-only just that one; --verify checks the
    # files already at the root without writing. --since=REF keeps the complete current Map but
    # selects source only from changed tracked paths; it requires --budget.
    def cli(argv)
      flags = FLAGS.to_h { |flag| [flag, argv.delete(flag)] }
      budget_arg = argv.find { |arg| arg.start_with?("--budget=") }
      part_bytes_arg = argv.find { |arg| arg.start_with?("--part-bytes=") }
      only_arg = argv.find { |arg| arg.start_with?("--only=") }
      since_arg = argv.find { |arg| arg.start_with?("--since=") }
      return usage_error("--budget must be a positive integer") if budget_arg &&
        (!budget_arg.match?(/\A--budget=\d+\z/) || budget_arg.split("=", 2).last.to_i <= 0)
      return usage_error("--part-bytes must be a positive integer") if part_bytes_arg &&
        (!part_bytes_arg.match?(/\A--part-bytes=\d+\z/) || part_bytes_arg.split("=", 2).last.to_i <= 0)
      return usage_error("--only needs at least one non-empty path") if only_arg && only_arg.split("=", 2).last.to_s.split(",").all?(&:empty?)
      return usage_error("--since needs a non-empty commit reference") if since_arg && since_arg.split("=", 2).last.to_s.empty?
      budget = budget_arg&.split("=", 2)&.last&.to_i
      part_bytes = part_bytes_arg&.split("=", 2)&.last&.to_i
      only = only_arg&.split("=", 2)&.last&.split(",")
      since = since_arg&.split("=", 2)&.last
      unknown = argv.select { |arg| arg.start_with?("--") && !arg.match?(/\A--(budget|part-bytes|only|since)=/) }
      return usage_error("unknown option #{unknown.first}") if unknown.any?

      trees = argv.reject { |arg| arg.start_with?("--") }.map(&:upcase)
      trees = TREES if trees.empty?
      bad = trees - TREES
      return usage_error("unknown tree #{bad.first}") if bad.any?
      if since && budget.nil?
        return usage_error("--since requires --budget=BYTES; incremental packs are reading copies, not full mirrors")
      end
      if since && (flags["--mirror"] || flags["--verify"])
        return usage_error("--since cannot be combined with --mirror or --verify")
      end
      return run(trees, mirror: true) if flags["--mirror"]
      return verify(trees, only:) if flags["--verify"]

      options = { tests: !flags["--tests"].nil?, full: budget.nil?, only:, part_bytes:, since: since,
                  variants: flags["--code-only"] ? [:code] : (flags["--code"] ? %i[exact code] : [:exact]) }
      options[:budget] = budget if budget
      run(trees, **options.compact)
    rescue Operator::SnapshotVerify::Failed => e
      warn e.message
      1
    rescue ArgumentError => e
      warn e.message
      2
    end

    def usage_error(message)
      warn "snapshot: #{message}\n#{USAGE}"
      2
    end

    # The variants a tree has at the root, each checked against the tracked files.
    def verify(trees, only: nil, io: $stdout)
      trees.each do |tree|
        names = Dir.children(REPO).grep(Operator::SnapshotParts.stale_pattern(tree))
        variants = names.map { |name| name.include?(".code") ? :code : :exact }.uniq
        raise Operator::SnapshotVerify::Failed, "snapshot0: #{tree} has no snapshot files at the root" if variants.empty?

        variants.each { |variant| Operator::SnapshotVerify.call(self, tree, variant:, only:, io:) }
      end

      0
    end
  end
end

exit Operator::Snapshot.cli(ARGV.dup) if $PROGRAM_NAME == __FILE__
