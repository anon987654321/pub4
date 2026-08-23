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
    START_HERE.md
    CHANGELOG.md
    RAILS/CLAUDE.md
    OPENBSD/CLAUDE.md
    OPENBSD/RUNBOOK.md
    MASTER/START_HERE.md
    MASTER/AGENTS.md
    MASTER/DECISIONS.md
    RAILS/shared/WIRING_NOTES.md
  ].freeze

  TREES = %w[MASTER RAILS OPENBSD STUDIO bin dotfiles].freeze
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
    TREES.include?(head) || File.exist?(File.join(REPO, head))
  end

  def cited_paths(doc)
    File.read(File.join(REPO, doc))
        .scan(/`([^`\s]+)`/).flatten
        .map { |c| c.sub(/[.,;:)]+\z/, "") }
        .reject { |c| c.match?(/[*${}<]/) }
        .reject { |c| KNOWN_ABSENT.include?(c) }
        .select { |c| repo_path?(c) }
        .uniq
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
