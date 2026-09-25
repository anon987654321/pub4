# frozen_string_literal: true

require_relative "test_helper"

# Every repo path a document cites must exist.
#
# Prose goes stale silently. RUNBOOK.md taught `MASTER/lib/reach/base.rb` for
# months after lib/reach became lib/io; CLAUDE.md was once deleted wholesale for
# describing a DEPLOY/ tree that no longer existed; bin/ci pointed at
# core/spec/core_smoke.rb for eleven days after core/ was folded into lib/.
# Each was found by a person tripping over it.
#
# Only backticked paths that look like repo paths are checked — a path is
# claimed here when it starts with a known tree or a known root file and carries
# a slash or a known extension. Prose about a path ("the lib/ folder") is not a
# citation and is not checked; neither is anything under a directory this repo
# does not track.
class TestDocPaths < Minitest::Test
  REPO = File.expand_path("../..", __dir__)

  # Docs an agent is actually pointed at. Adding one here is the point: a
  # document nobody reads does not need this guard, and a document that teaches
  # a path does.
  # TODO.md is deliberately not here, and the reason is measured rather than an
  # omission. It cites 428 repo paths; 34 of them name subjects that are gone on
  # purpose — MASTER/DEBT.md, RAILS/BLOCKERS.md, docs/SEVERANCE.md, the deleted
  # io/lora_pipeline.rb — because a register that records what was removed has to
  # be able to say what it was. A gate demanding every cited path exist would
  # need a 34-row baseline that a fresh entry breaks the same week, and would
  # turn the register's own function into a red gate. Its citations go stale as
  # numbers rather than as paths, which is why every section carries the date it
  # was measured.
  DOCS = %w[
    CLAUDE.md
    TREE.md
    AGENTS.md
    GEMINI.md
    .cursorrules
    .github/copilot-instructions.md
    MASTER/README.md
    MASTER/AGENTS.md
    OPENBSD/README.md
    OPENBSD/RUNBOOK.md
    RAILS/README.md
    RAILS/CLAUDE.md
    MASTER/tools/README.md
  ].freeze

  # Every coding agent reads a different file, and pub4 had one of the five.
  # An agent that never sees MASTER's law does not follow it however well the
  # law is written, so the four harness files are generated from one marked
  # block in MASTER/AGENTS.md. This asserts they exist and still point at the
  # law; rake lint:agent_contracts asserts they are byte-identical to it.
  HARNESS_FILES = %w[
    AGENTS.md GEMINI.md .cursorrules .github/copilot-instructions.md
  ].freeze

  # Human documentation has one shape: README.md at the thing it documents.
  # The deliberate exceptions are machine-facing agent contracts, the constitutional
  # data mirrors, the root backlog/map, and the OpenBSD live-operation runbook.
  def test_markdown_stays_at_meaningful_boundaries
    tracked_md = tracked.select { |path| path.end_with?(".md") }
    extras = tracked_md.reject do |path|
      File.basename(path) == "README.md" ||
        path == "TODO.md" || path == "TREE.md" ||
        File.basename(path).match?(/\A(?:AGENTS|CLAUDE|GEMINI)\.md\z/) ||
        path == ".github/copilot-instructions.md" ||
        path == "OPENBSD/RUNBOOK.md" ||
        path.match?(%r{\AMASTER/data/(?:SOUL|IDENTITY|CANON)\.md\z})
    end

    assert_empty extras,
                 "non-README Markdown needs a documented exception: #{extras.join(", ")}"
  end

  def test_every_harness_file_points_at_the_law
    missing = HARNESS_FILES.reject { |relative| File.file?(File.join(REPO, relative)) }

    assert_empty missing, "no entry file for an agent that reads it: #{missing.join(", ")}"

    HARNESS_FILES.each do |relative|
      body = File.read(File.join(REPO, relative))

      assert_includes body, "MASTER/data/soul.yml", "#{relative} does not name the kernel" # source-assertion: ok — a document has no behaviour but its text
      assert_includes body, "MASTER/data/rules.yml", "#{relative} does not name the rule catalogue" # source-assertion: ok — a document has no behaviour but its text
      assert_includes body, "docs:agent_contracts", # source-assertion: ok — a document has no behaviour but its text
                      "#{relative} does not say where it came from"
    end
  end

  # The one an agent reading CLAUDE.md must not miss: this file is not the
  # authority, and it has to say so where it is read rather than in a commit.
  def test_claude_md_says_master_outranks_it
    body = File.read(File.join(REPO, "CLAUDE.md"))

    assert_includes body, "MASTER is the primary configuration" # source-assertion: ok — a document has no behaviour but its text
    # Not "rake docs:…": the sentence wraps between the two words in CLAUDE.md,
    # and an assertion that fails on a line break is testing the paragraph.
    assert_includes body, "docs:agent_contracts" # source-assertion: ok — a document has no behaviour but its text
  end

  # The repo root has three governed trees and CLAUDE.md. bin/ moved under MASTER and
  # dotfiles/ under OPENBSD, so neither is a top-level tree any more.
  TREES = %w[MASTER RAILS OPENBSD].freeze
  # Paths that name a thing on the VPS, not a thing in the repo.
  ABSOLUTE_OR_REMOTE = %r{\A(/|~|https?:|[a-z]+@)}

  # Deliberately absent, and named on purpose. A changelog that records a
  # deletion has to be able to say what was deleted.
  KNOWN_ABSENT = %w[
    bin/snapshot
    MASTER/output/
    MASTER/knowledge/
  ].freeze

  def repo_path?(candidate)
    return false if candidate.match?(ABSOLUTE_OR_REMOTE)
    return false unless candidate.include?("/") || candidate.match?(/\.\w{1,5}\z/)

    head = candidate.split("/").first
    return true if TREES.include?(head) || File.exist?(File.join(REPO, head))

    # A head that exists beside the document. MASTER/README.md writes
    # `data/rules.yml` and means MASTER's, which resolves against the repo root
    # as a `data` tree that does not exist — so without this every citation a
    # MASTER or OPENBSD document makes of its own subdirectory is dropped before
    # it is checked.
    dir = File.dirname(@current_doc.to_s)
    return true if dir != "." && File.exist?(File.join(REPO, dir, head))

    # A head that resolves nowhere is usually prose — but it is also exactly what
    # a deleted directory leaves behind, and that is when this check matters
    # most. `docs/SEVERANCE.md` was cited as a source of truth by two governing
    # documents for weeks: docs/ had been deleted, so the token was dropped as
    # "not a path" before anything looked for the file. The gate written to catch
    # a stale citation was blind to the one kind of staleness it cannot recover
    # from.
    #
    # An extension is what separates the two. This repo's own file kinds only:
    # a mime type in prose (application/json) carries none, and a bare word with
    # a slash is not a citation.
    CITED_EXTENSIONS.include?(File.extname(candidate))
  end

  CITED_EXTENSIONS = %w[.md .rb .yml .yaml .scss .css .js .erb .rake .sh].freeze

  # Per-document exemptions, each with the argument for it, in
  # MASTER/data/doc_baselines.yml under `doc_paths:`. KNOWN_ABSENT above is
  # repo-wide and needs no reason — there is nothing to say about output/ and
  # knowledge/ — while a path one document may cite and another may not is a
  # judgement somebody has to defend.
  #
  # That file had no reader. `data_reach` reported `doc_baselines.yml#doc_paths`
  # as a key no code names and was right: this test carried its own list and
  # three careful paragraphs governed nothing. The rows are still correct — a
  # public key .gitignore explicitly un-ignores and has not been added yet, and
  # a worked example naming the design_rules.yml whose folding it teaches.
  BASELINE = File.expand_path("../data/doc_baselines.yml", __dir__)

  def exempt_for(doc)
    @exempt ||= YAML.safe_load_file(BASELINE)["doc_paths"] || {}
    Array(@exempt[doc]).filter_map { |row| row["path"] }
  end

  def cited_paths(doc)
    @current_doc = doc
    exempt = KNOWN_ABSENT + exempt_for(doc)
    File.read(File.join(REPO, doc))
        .scan(/`([^`\s]+)`/).flatten
        .map { |c| c.sub(/[.,;:)]+\z/, "") }
        # `lib/builder.rb:165` cites lib/builder.rb. Without this the trailing
        # line number makes the extension unrecognisable, so the whole citation
        # is dropped as prose — and the file:line form is how this repo's
        # documents point at code, which left the commonest citation shape
        # outside the gate written to check citations.
        .map { |c| c.sub(/:\d+(?:-\d+)?\z/, "") }
        .reject { |c| c.match?(/[*${}<]/) }
        .reject { |c| exempt.include?(c) }
        .select { |c| repo_path?(c) }
        .uniq
  end

  # An exemption for a document nobody checks governs nothing, and an exemption
  # naming a path that has appeared is one the tree has outgrown. Both are how
  # the baseline stopped being read in the first place.
  def test_every_exemption_still_has_a_subject
    baseline = YAML.safe_load_file(BASELINE)["doc_paths"] || {}
    stale = baseline.flat_map do |doc, rows|
      Array(rows).filter_map do |row|
        next "#{doc}: no such document" unless File.exist?(File.join(REPO, doc))

        "#{doc}: #{row["path"]} exists now — drop the exemption" if resolves?(row["path"], doc)
      end
    end

    assert_empty stale.uniq, "doc_baselines.yml doc_paths entries with nothing to exempt:\n  #{stale.uniq.join("\n  ")}"
  end

  # A citation resolves from the repo root, from the document's own directory,
  # or as the tail of a tracked path — because `bin/ci` in OPENBSD/CLAUDE.md
  # means the one in RAILS, and requiring every doc to spell full paths would
  # make the prose worse to read in order to make this test easier to write.
  def resolves?(candidate, doc)
    return true if File.exist?(File.join(REPO, candidate))
    return true if File.exist?(File.expand_path(candidate, File.join(REPO, File.dirname(doc))))
    return true if tracked.any? { |t| t.end_with?("/#{candidate}") || t == candidate }

    generated?(candidate, doc)
  end

  # A path the repo ignores is generated, and a clean checkout is entitled not to
  # have it. `web/storage/` and `web/log/` are Rails' own runtime directories and
  # MASTER/README.md lists them under "Local/generated", which is the citation this
  # gate is least able to check and most likely to punish: the prose is correct
  # and the directory only appears after the app has run once.
  #
  # A live query rather than another allow-list entry, because an exemption whose
  # subject no longer exists is a hole nobody can see — this one goes stale the
  # day the ignore rule does, on its own.
  #
  # From the document's own directory only, which is the reading `resolves?`
  # already takes of a citation. The repo-root reading would be wrong in one case
  # that matters: `.gitignore` excludes `priv/ssh/` and then un-excludes
  # `!priv/ssh/*.pub`, but git cannot re-include a file inside an excluded
  # directory, so the root form of that public key reads as ignored while
  # `OPENBSD/priv/ssh/…` does not. The operator's decision there is that the file
  # is missing and should be added, which is a citation this gate must keep.
  def generated?(candidate, doc)
    Dir.chdir(REPO) { system("git", "check-ignore", "-q", File.join(File.dirname(doc), candidate)) }
  end

  def tracked
    @tracked ||= Dir.chdir(REPO) { `git ls-files`.lines.map(&:strip) }
  end

  # Both directions, because a predicate that answered true for everything would
  # switch this gate off while reading exactly like a fix.
  def test_only_an_ignored_path_counts_as_generated
    assert generated?("web/storage/", "MASTER/README.md"),
           "MASTER/web/.gitignore names storage, so a clean checkout cannot be asked for it"
    refute generated?("web/nowhere/", "MASTER/README.md"),
           "a path nothing ignores is a citation this gate must still check"
    refute generated?("priv/ssh/id_ed25519_brgen.pub", "OPENBSD/RUNBOOK.md"),
           "the root reading of that path is ignored and the document's reading is not"
  end

  def test_every_repo_path_a_doc_cites_exists
    missing = DOCS.each_with_object({}) do |doc, acc|
      next unless File.exist?(File.join(REPO, doc))

      gone = cited_paths(doc).reject { |c| resolves?(c, doc) }
      acc[doc] = gone if gone.any?
    end

    assert_empty missing,
                 "these documents cite repo paths that do not exist — fix the path or the prose:\n" +
                 missing.map { |doc, paths| "  #{doc}\n    #{paths.join("\n    ")}" }.join("\n")
  end

  # The list above is only useful if it names documents that are there.
  def test_the_document_list_is_not_stale
    absent = DOCS.reject { |doc| File.exist?(File.join(REPO, doc)) }

    assert_empty absent, "DOCS names documents that no longer exist: #{absent.join(', ')}"
  end
end
