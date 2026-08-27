# frozen_string_literal: true

# Regenerates the verbatim codebase mirrors at pub4/snapshot_<TREE>.md.
#
# These are the packs handed to another model when it needs the whole tree
# rather than a summary: every git-tracked text file inlined in full, no size
# cap, plus a tree listing and the reading protocol.
#
# The generator that made them was `bin/snapshot`, deleted with the DEPLOY tree
# in the OPENBSD reorganisation — so the three files sat eleven days stale at a
# commit that no longer exists in any working checkout, with nothing able to
# refresh them. This lives in tools/ and is reachable as `MASTER/bin/pub4 snapshot`,
# which is the surface an operator already has.
#
# Binary files are listed in the tree and skipped in the body; a mirror that
# claims to inline everything must say which files it could not.

require "fileutils"
require "open3"

module Pub4
  module Snapshot
    REPO = File.expand_path("../..", __dir__)
    TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze

    # Extension → fence language. Anything unlisted gets a bare fence.
    FENCE = {
      ".rb" => "ruby", ".rake" => "ruby", ".gemspec" => "ruby", ".ru" => "ruby",
      ".yml" => "yaml", ".yaml" => "yaml", ".json" => "json",
      ".js" => "javascript", ".mjs" => "javascript", ".ts" => "typescript",
      ".css" => "css", ".scss" => "scss", ".html" => "html", ".erb" => "erb",
      ".md" => "markdown", ".sh" => "bash", ".zsh" => "bash", ".ksh" => "bash",
      ".sql" => "sql", ".conf" => "conf", ".toml" => "toml"
    }.freeze

    module_function

    def tracked(tree)
      out, status = Open3.capture2("git", "ls-files", "-z", tree, chdir: REPO)
      raise "git ls-files failed for #{tree}" unless status.success?

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

        This document is a **verbatim codebase mirror** for `#{tree}`. Treat every fenced
        block as source of truth — not a summary. Work through it in this order:

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
        4. Every git-tracked **text** file is inlined in full — no size cap. Binary files are listed
           under **Binary files** and are not inlined.
        5. Repeat for every sibling `snapshot_*.md` present — each extracts to its own subtree.
        6. Verify: file count vs Tree, spot-check sizes, run targeted tests from the mirrored tree.

        Do not edit the mirrored tree until you have a written assessment and a trace for the path
        you intend to change.
      MD
    end

    def write(tree, io: $stdout)
      paths = tracked(tree)
      return io.puts("snapshot: #{tree} has no tracked files — skipped") if paths.empty?

      binaries, texts = paths.partition { |p| binary?(File.join(REPO, p)) }
      # MASTER/output, not the repo root. The root is four trees and one file,
      # and a tool that drops four generated markdown files beside them makes
      # that untrue every time it runs -- gitignored, so the tracked state stayed
      # right while the working directory did not.
      dir = File.join(REPO, "MASTER", "output")
      FileUtils.mkdir_p(dir)
      out = File.join(dir, "snapshot_#{tree}.md")

      File.open(out, "w") do |f|
        f.puts "# #{tree} — source snapshot"
        f.puts
        f.puts "Generated #{Time.now.utc.strftime('%Y-%m-%d %H:%M UTC')} · git #{head_sha} · " \
               "#{texts.size} files inlined in full (no size cap)" \
               "#{binaries.empty? ? '' : ", #{binaries.size} binary listed only"}."
        f.puts
        f.puts protocol(tree)
        f.puts "## Tree"
        f.puts "```"
        paths.each { |p| f.puts p }
        f.puts "```"
        unless binaries.empty?
          f.puts
          f.puts "## Binary files"
          f.puts
          f.puts "Listed, not inlined:"
          f.puts
          binaries.each { |p| f.puts "- `#{p}`" }
        end
        f.puts
        texts.each do |p|
          body = File.read(File.join(REPO, p), encoding: "UTF-8")
          # A file containing a fence run must not break out of its own block.
          longest = body.scan(/^`{3,}/).map(&:length).max.to_i
          fence = "`" * [3, longest + 1].max
          f.puts "## `#{p}`"
          f.puts
          f.puts "#{fence}#{FENCE.fetch(File.extname(p), '')}"
          f.write(body)
          f.puts unless body.end_with?("\n")
          f.puts fence
          f.puts
        end
      end

      io.puts format("snapshot: %-8s %5d files (%d binary) → %s (%.1f MB)",
                     tree, paths.size, binaries.size, out.delete_prefix(REPO + "/"),
                     File.size(out) / 1_048_576.0)
    end

    def run(trees = TREES, io: $stdout)
      trees.each { |t| write(t, io:) }
      0
    end
  end
end

exit Pub4::Snapshot.run(ARGV.empty? ? Pub4::Snapshot::TREES : ARGV) if $PROGRAM_NAME == __FILE__
