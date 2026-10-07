# frozen_string_literal: true

# Regenerates the verbatim codebase mirrors at the pub4 root: snapshot_MASTER.md,
# snapshot_RAILS.md, snapshot_OPENBSD.md and snapshot_STUDIO.md.
#
# These are the packs handed to another model when it needs the whole tree
# rather than a summary: every git-tracked text file inlined when the share pack fits the hard size
# ceiling, plus a tree listing, omitted-file ledger and the reading protocol.
#
# The generator that made them was `bin/snapshot`, deleted with the DEPLOY tree
# in the OPENBSD reorganisation — so the source mirrors sat stale at a
# commit that no longer exists in any working checkout, with nothing able to
# refresh them. This lives in tools/ and is reachable as `MASTER/bin/operator snapshot`,
# which is the surface an operator already has.
#
# Binary files are listed in the tree and skipped in the body; a mirror that
# claims to inline everything must say which files it could not.

require "fileutils"
require "open3"
require_relative "../lib/trace/dmesg"

module Operator
  module Snapshot
    REPO = File.expand_path("../..", __dir__)
    TREE_PATHS = {
      "MASTER" => "MASTER",
      "RAILS" => "RAILS",
      "OPENBSD" => "OPENBSD",
      "STUDIO" => "STUDIO"
    }.freeze
    OUTPUT_NAMES = {
      "MASTER" => "snapshot_MASTER.md",
      "RAILS" => "snapshot_RAILS.md",
      "OPENBSD" => "snapshot_OPENBSD.md",
      "STUDIO" => "snapshot_STUDIO.md"
    }.freeze
    TREES = TREE_PATHS.keys.freeze
    MAX_BYTES = 9_500_000
    MANDATORY_PATHS = %w[
      MASTER/README.md
      MASTER/data/soul.yml
      MASTER/data/laws.yml
      MASTER/tools/snapshot.rb
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

    def tracked(tree)
      path = TREE_PATHS.fetch(tree) { raise "snapshot: unknown tree #{tree.inspect}" }
      out, status = Open3.capture2("git", "ls-files", "-z", path, chdir: REPO)
      raise "git ls-files failed for #{tree} (#{path})" unless status.success?

      out.split("\0").reject(&:empty?).sort
    end

    def binary?(path)
      head = File.binread(path, 8000).to_s
      return true if head.include?("\0")

      head.force_encoding(Encoding::UTF_8)
      !head.valid_encoding?
    rescue StandardError
      true
    end

    def head_sha
      Open3.capture2("git", "rev-parse", "--short", "HEAD", chdir: REPO).first.strip
    end

    def protocol(tree)
      <<~MD
        Share this file with another LLM as the full readable #{tree} codebase pack.

        ## Agent analysis protocol

        This document is a **share-size-bounded source mirror** for `#{tree}`. Treat every fenced
        block as source of truth — not a summary. The `Omitted text files` section, when present,
        is authoritative: those tracked text files were excluded only to satisfy the hard size ceiling. Work through it in this order:

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
        4. Every tracked **text** file not named under `Omitted text files` is inlined in full. Binary files
           are listed under **Binary files** and are not inlined.
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
        4. `MASTER/lib/review/scan/rules/*.rb` — the executable scan registry; inspect its live registry rather than a remembered count.

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

    def omission_priority(path)
      return 0 if path.match?(%r{/(?:vendor|public/vendor)/})
      return 0 if path.match?(/(?:\.bundle|\.min)\.(?:js|css)\z/)
      return 0 if path.end_with?(".map")
      return 5 if path == "MASTER/web/public/three.face.module.js"
      return 20 if path.start_with?("MASTER/web/public/") && !path.match?(/face|chat/i)
      return 100
    end

    def mandatory?(path)
      MANDATORY_PATHS.include?(path) ||
        path.start_with?("MASTER/law/", "MASTER/lib/review/scan/rules/")
    end

    def render_snapshot(tree, paths, binaries, texts, omitted, sha)
      fence3 = 96.chr * 3
      out = String.new
      out << "# #{tree} — source snapshot\n\n"
      out << "Generated #{Time.now.utc.strftime('%Y-%m-%d %H:%M UTC')} — git #{sha} — "
      out << "#{texts.size} files inlined"
      out << ", #{binaries.size} binary listed only" unless binaries.empty?
      out << ", #{omitted.size} text omitted for share-size" unless omitted.empty?
      out << ".\n\n"
      out << protocol(tree)
      out << "## Tree\n#{fence3}\n"
      paths.each { |p| out << "#{p}\n" }
      out << "#{fence3}\n"
      unless binaries.empty?
        out << "\n## Binary files\n\nListed, not inlined:\n\n"
        binaries.each { |p| out << "- #{96.chr}#{p}#{96.chr}\n" }
      end
      unless omitted.empty?
        out << "\n## Omitted text files\n\nThese tracked text files are deliberately omitted only to keep this share pack below the hard 9.5 MB ceiling.\n\n"
        omitted.each { |p| out << "- #{96.chr}#{p}#{96.chr} — #{File.size(File.join(REPO, p))} bytes\n" }
      end
      out << "\n"
      texts.each do |p|
        body = File.read(File.join(REPO, p), encoding: "UTF-8")
        longest = body.scan(/^`{3,}/).map(&:length).max.to_i
        fence = 96.chr * [3, longest + 1].max
        out << "## #{96.chr}#{p}#{96.chr}\n\n"
        out << "#{fence}#{FENCE.fetch(File.extname(p), "")}\n"
        out << body
        out << "\n" unless body.end_with?("\n")
        out << "#{fence}\n\n"
      end
      out << "## Snapshot complete\n\n"
      out << "snapshot0: complete tree=#{tree} files=#{paths.size} text=#{texts.size} binary=#{binaries.size} omitted=#{omitted.size} bytes=#{out.bytesize}\n"
      out
    end

    def write(tree, io: $stdout)
      paths = tracked(tree)
      if paths.empty?
        Master::Trace::Dmesg.status("snapshot0", "#{tree}, no tracked files, skipped", io:)
        return
      end

      binaries, texts = paths.partition { |p| binary?(File.join(REPO, p)) }
      omitted = []
      sha = head_sha

      loop do
        candidate = texts.reject { |p| mandatory?(p) || omitted.include?(p) }
          .sort_by { |p| [omission_priority(p), -File.size(File.join(REPO, p)), p] }
          .first
        final_texts = texts.reject { |p| omitted.include?(p) }
        probe = render_snapshot(tree, paths, binaries, final_texts, omitted, sha)
        break if probe.bytesize <= MAX_BYTES
        raise "snapshot: #{tree} cannot fit below #{MAX_BYTES} bytes without omitting mandatory files" unless candidate
        omitted << candidate
      end

      final_texts = texts.reject { |p| omitted.include?(p) }
      out = File.join(REPO, OUTPUT_NAMES.fetch(tree))
      File.write(out, render_snapshot(tree, paths, binaries, final_texts, omitted, sha), encoding: "UTF-8")

      Master::Trace::Dmesg.status(
        "snapshot0",
        "#{tree}, #{paths.size} files, #{final_texts.size} text, #{binaries.size} binary, #{omitted.size} omitted, #{out.delete_prefix(REPO + "/")}, #{(File.size(out) / 1_000_000.0).round(2)} MB",
        io:
      )
    end

    def run(trees = TREES, io: $stdout)
      trees.each { |t| write(t, io:) }
      0
    end
  end
end

exit Operator::Snapshot.run(ARGV.empty? ? Operator::Snapshot::TREES : ARGV) if $PROGRAM_NAME == __FILE__
