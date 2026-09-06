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
  DOCS = %w[
    CLAUDE.md
    AGENTS.md
    GEMINI.md
    .cursorrules
    .github/copilot-instructions.md
    RAILS/CLAUDE.md
    OPENBSD/CLAUDE.md
    OPENBSD/RUNBOOK.md
    MASTER/START_HERE.md
    MASTER/AGENTS.md
    MASTER/DECISIONS.md
    RAILS/shared/WIRING_NOTES.md
  ].freeze

  # Every coding agent reads a different file, and pub4 had one of the five.
  # An agent that never sees MASTER's law does not follow it however well the
  # law is written, so the four harness files are generated from one marked
  # block in MASTER/AGENTS.md. This asserts they exist and still point at the
  # law; rake lint:agent_contracts asserts they are byte-identical to it.
  HARNESS_FILES = %w[
    AGENTS.md GEMINI.md .cursorrules .github/copilot-instructions.md
  ].freeze

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

  # The repo root is four trees and CLAUDE.md. bin/ moved under MASTER and
  # dotfiles/ under OPENBSD, so neither is a top-level tree any more.
  TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze
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

    # A head that exists beside the document. MASTER/DECISIONS.md writes
    # `data/rules.yml` and means MASTER's, which resolved against the repo root
    # as a `data` tree that does not exist — so every citation a MASTER or
    # OPENBSD document made of its own subdirectory was dropped before it was
    # checked. Seven stale ones were sitting behind that, four of them in the
    # decision records.
    dir = File.dirname(@current_doc.to_s)
    dir != "." && File.exist?(File.join(REPO, dir, head))
  end

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
  # two decision records naming the design_rules.yml they record the folding of.
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

    tracked.any? { |t| t.end_with?("/#{candidate}") || t == candidate }
  end

  def tracked
    @tracked ||= Dir.chdir(REPO) { `git ls-files`.lines.map(&:strip) }
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
