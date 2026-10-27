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
  # the old backlog is deliberately not here, and the reason is measured rather than an
  # omission. It cites 428 repo paths; 34 of them name subjects that are gone on
  # purpose — MASTER/DEBT.md, RAILS/BLOCKERS.md, docs/SEVERANCE.md, the deleted
  # io/lora_pipeline.rb — because a register that records what was removed has to
  # be able to say what it was. A check demanding every cited path exist would
  # need a 34-row baseline that a fresh entry breaks the same week, and would
  # turn the register's own function into a red check. Its citations go stale as
  # numbers rather than as paths, which is why every section carries the date it
  # was measured.
  DOCS = %w[
    README.md
    CLAUDE.md
    AGENTS.md
    GEMINI.md
    .cursorlaws
    .github/copilot-instructions.md
    MASTER/README.md
    MASTER/AGENTS.md
    OPENBSD/README.md
    OPENBSD/RUNBOOK.md
    RAILS/README.md
    RAILS/CLAUDE.md
    MASTER/tools/README.md
    STUDIO/README.md
  ].freeze

  def test_design_authority_is_laws_yml_without_a_parallel_architecture_document
    refute File.exist?(File.join(REPO, "ARCHITECTURE.md"))

    root_readme = File.read(File.join(REPO, "README.md"))
    assert_includes root_readme, "`MASTER/data/laws.yml`"
    refute_match(/\]\(ARCHITECTURE\.md\)/, root_readme)
  end

  def test_authority_order_puts_executable_law_above_harnesses
    docs = %w[CLAUDE.md MASTER/AGENTS.md RAILS/CLAUDE.md OPENBSD/CLAUDE.md]
    docs.each do |doc|
      body = File.read(File.join(REPO, doc))
      soul = body.index("MASTER/data/soul.yml")
      laws = body.index("MASTER/data/laws.yml")
      assert soul && laws && soul < laws, "#{doc} must put soul.yml before laws.yml"
      # Each names MASTER/law/ as the Ruby that enforces the catalogue, below it.
      enforcement = body.index(%r{(?:executable law|ruby)\b[^\n]*MASTER/law/}i)
      assert enforcement && enforcement > laws, "#{doc} must name MASTER/law/ as enforcement after laws.yml"
    end

    root = File.read(File.join(REPO, "CLAUDE.md"))
    refute_match(/MASTER\/data\/rules\.yml`? > this file >.*executable law/i, root)
  end

  # Every coding agent reads a different file, and pub4 had one of the five.
  # An agent that never sees MASTER's law does not follow it however well the
  # law is written, so the four harness files are generated from one marked
  # block in MASTER/AGENTS.md. This asserts they exist and still point at the
  # law; rake lint:agent_contracts asserts they are byte-identical to it.
  HARNESS_FILES = %w[
    AGENTS.md GEMINI.md .cursorlaws .github/copilot-instructions.md
  ].freeze

  # Non-entry Markdown has a narrow purpose: face/reference contracts, archived
  # RAILS experiments and research, recovery material, and STUDIO migration guides.
  # docs/runbooks and docs/todo-triage.md are the evidence procedures TODO.md cites;
  # MASTER/docs/handoffs holds preserved run logs and the archived predecessor ledger.
  # These are artifacts, not substitutes for tree/project README entry points.
  # MASTER/docs holds the execution-contract references that TODO.md, the code
  # comments and the lifecycle work cite by path.
  MARKDOWN_REFERENCE_EXCEPTIONS = %w[
    MASTER/FACE_WORLD.md
    MASTER/data/principles/openbsd_kernel_philosophy.md
    MASTER/docs/execution-contracts.md
    MASTER/docs/fix_coordinator_map.md
    MASTER/docs/handoffs/2026-10-26-master-hardening-review.md
    MASTER/docs/laws_digest.md
    MASTER/docs/lifecycle_ownership.md
    MASTER/docs/mobile.md
    MASTER/docs/restructure_assessment.md
    MASTER/docs/handoffs/2026-10-22-laws-checks-rails-fix.md
    MASTER/docs/handoffs/legacy/MEGA_ALL_APPS.md
    MASTER/lib/cli/face/contract.md
    RAILS/INTERACTION_CAMPAIGN.md
    RAILS/__shared/LAYOUT_MICRO_REFINEMENT_MATRIX.md
    RAILS/__shared/SOCIAL_FRONT_PAGE.md
    RAILS/__shared/SURFACE_MICRO_REFINEMENT_MATRIX.md
    RAILS/__shared/SURFACE_MICRO_REFINEMENT_MATRIX_II.md
    RAILS/__shared/UI_ARCHAEOLOGY.md
    RAILS/__shared/UI_ARCHAEOLOGY_II.md
    STUDIO/dilla/ENGINE_NOTES.md
    STUDIO/dilla/REFERENCE_STUDY.md
    STUDIO/postpro/LEGACY_RESTORE.md
    STUDIO/replicate/lora/guides/photography.md
    STUDIO/replicate/lora/guides/prompting.md
    docs/runbooks/cli-web-ux.md
    docs/runbooks/openbsd-deploy-restore.md
    docs/runbooks/provider-integration.md
    docs/runbooks/pwa.md
    docs/runbooks/release-pass.md
    docs/runbooks/rendered-layout.md
    docs/runbooks/studio-render.md
    docs/runbooks/voice-path.md
    docs/todo-triage.md
  ].freeze

  # README.md is the human entry point at each tree/project boundary. Other
  # Markdown survives only when it has a distinct runtime, archive, or recovery job.
  def test_markdown_stays_at_meaningful_boundaries
    tracked_md = tracked.select { |path| path.end_with?(".md") }
    stale_exceptions = MARKDOWN_REFERENCE_EXCEPTIONS - tracked
    assert_empty stale_exceptions,
                 "remove retired Markdown reference exceptions: #{stale_exceptions.join(", ")}"

    extras = tracked_md.reject do |path|
      File.basename(path) == "README.md" ||
        path == "TODO.md" ||
        File.basename(path).match?(/\A(?:AGENTS|CLAUDE|GEMINI)\.md\z/) ||
        path == ".github/copilot-instructions.md" ||
        path == "OPENBSD/RUNBOOK.md" ||
        path.match?(%r{\AMASTER/data/(?:SOUL|IDENTITY|CANON)\.md\z}) ||
        MARKDOWN_REFERENCE_EXCEPTIONS.include?(path)
    end

    assert_empty extras,
                 "non-README Markdown needs a documented exception: #{extras.join(", ")}"
  end

  def test_agent_contract_does_not_ban_the_managed_worktree_workflow
    source = File.read(File.join(REPO, "MASTER/AGENTS.md"))
    block = source[/<!-- agent-contract:begin -->\n(.*?)<!-- agent-contract:end -->/m, 1]
    refute_nil block

    refute_match(/branches and pull requests are refused|write straight to `main`|block_branching/, block)
    assert_includes block, "Use isolated, managed worktrees"
    assert_includes block, "pushes only the current branch"

    HARNESS_FILES.each do |relative|
      body = File.read(File.join(REPO, relative))
      refute_match(/branches and pull requests are refused|block_branching/, body, "#{relative} retains the removed restriction")
      assert_includes body, "Use isolated, managed worktrees", "#{relative} does not teach the active workflow"
    end
  end

  def test_every_harness_file_points_at_the_law
    missing = HARNESS_FILES.reject { |relative| File.file?(File.join(REPO, relative)) }

    assert_empty missing, "no entry file for an agent that reads it: #{missing.join(", ")}"

    HARNESS_FILES.each do |relative|
      body = File.read(File.join(REPO, relative))

      assert_includes body, "MASTER/data/soul.yml", "#{relative} does not name the kernel" # source-assertion: ok — a document has no behaviour but its text
      assert_includes body, "MASTER/data/laws.yml", "#{relative} does not name the rule catalogue" # source-assertion: ok — a document has no behaviour but its text
      assert_includes body, "docs:agent_contracts", # source-assertion: ok — a document has no behaviour but its text
                      "#{relative} does not say where it came from"
    end
  end

  # The one an agent reading CLAUDE.md must not miss: this file is not the
  # authority, and it has to say so where it is read rather than in a commit.
  def test_claude_md_says_master_outranks_it
    body = File.read(File.join(REPO, "CLAUDE.md"))

    # source-assertion: ok — a document has no behaviour but its text
    assert_includes body, "MASTER is Claude's #1 primary configuration"
    # It points at the soul and the Law catalogue rather than restating them.
    %w[MASTER/data/soul.yml MASTER/data/laws.yml].each do |path|
      # source-assertion: ok — a document has no behaviour but its text
      assert_includes body, path
    end
  end

  # The repo root has four governed trees and CLAUDE.md. bin/ moved under MASTER and
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

    # A head that exists beside the document. MASTER/README.md writes
    # `data/laws.yml` and means MASTER's, which resolves against the repo root
    # as a `data` tree that does not exist — so without this every citation a
    # MASTER or OPENBSD document makes of its own subdirectory is dropped before
    # it is checked.
    dir = File.dirname(@current_doc.to_s)
    return true if dir != "." && File.exist?(File.join(REPO, dir, head))

    # A head that resolves nowhere is usually prose — but it is also exactly what
    # a deleted directory leaves behind, and that is when this check matters
    # most. `docs/SEVERANCE.md` was cited as a source of truth by two governing
    # documents for weeks: docs/ had been deleted, so the token was dropped as
    # "not a path" before anything looked for the file. The check written to catch
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
  # a worked example naming the design_laws.yml whose folding it teaches.
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
        # outside the check written to check citations.
        .map { |c| c.sub(/:\d+(?:-\d+)?\z/, "") }
        # `data/laws.yml#visual_identity_contract` cites the file; the fragment names a key in it.
        .map { |c| c.sub(/#[^\/]*\z/, "") }
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
  # check is least able to check and most likely to punish: the prose is correct
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
  # is missing and should be added, which is a citation this check must keep.
  def generated?(candidate, doc)
    Dir.chdir(REPO) { system("git", "check-ignore", "-q", File.join(File.dirname(doc), candidate)) }
  end

  def tracked
    @tracked ||= Dir.chdir(REPO) { `git ls-files`.lines.map(&:strip) }
  end

  # Both directions, because a predicate that answered true for everything would
  # switch this check off while reading exactly like a fix.
  def test_only_an_ignored_path_counts_as_generated
    assert generated?("storage/", "RAILS/master/README.md"),
           "RAILS/master/.gitignore names storage, so a clean checkout cannot be asked for it"
    refute generated?("nowhere/", "RAILS/master/README.md"),
           "a path nothing ignores is a citation this check must still check"
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

  # The entry documents are interfaces: a broken local link is a dead control.
  # External availability is not claimed by this deterministic, offline check.
  def test_local_markdown_links_resolve
    broken = DOCS.each_with_object([]) do |doc, errors|
      next unless doc.end_with?(".md") && File.file?(File.join(REPO, doc))

      body = File.read(File.join(REPO, doc))
      body.scan(/!?\[[^\]]*\]\(\s*(?:<([^>\n]+)>|([^\s)]+))/).each do |angled, bare|
        target = angled || bare
        next if target.match?(/\A(?:https?:|mailto:|tel:|data:|\/\/)/i) || target.start_with?("/")

        path = target.split(/[?#]/, 2).first
        next if path.empty?

        errors << "#{doc}: broken local Markdown link #{target.inspect}" unless resolves?(path, doc)
      end
    end

    assert_empty broken, "maintained entry documents contain broken local links:\n  #{broken.join("\n  ")}"
  end

  def test_fenced_markdown_blocks_are_balanced
    broken = DOCS.filter_map do |doc|
      next unless doc.end_with?(".md") && File.file?(File.join(REPO, doc))

      opened = unclosed_fence(File.read(File.join(REPO, doc), encoding: "UTF-8"))
      next unless opened

      "#{doc}: unclosed #{opened[:fence].inspect} fence opened on line #{opened[:line]}"
    end

    assert_empty broken,
                 "maintained entry documents contain unclosed fenced code blocks:\n  #{broken.join("\n  ")}"
  end

  def test_fence_checker_matches_marker_and_opening_length
    assert_nil unclosed_fence("~~~text\n\x60\x60\x60 is content, not a tilde fence\n~~~~\n")
    assert_nil unclosed_fence("\x60\x60\x60ruby\nputs :ok\n\x60\x60\x60\n")

    opened = unclosed_fence("\x60\x60\x60\x60ruby\n\x60\x60\x60\n")
    assert_equal "\x60\x60\x60\x60", opened[:fence]
    assert_equal 1, opened[:line]
  end

  def unclosed_fence(body)
    opening = nil
    body.each_line.with_index(1) do |raw_line, number|
      line = raw_line.chomp
      if opening
        closer = /\A {0,3}#{Regexp.escape(opening[:marker])}{#{opening[:length]},}[ \t]*\z/
        opening = nil if line.match?(closer)
      elsif (match = line.match(/\A {0,3}(\x60{3,}|~{3,})(.*)\z/))
        # CommonMark forbids a backtick in a backtick fence's info string.
        next if match[1].start_with?("\x60") && match[2].include?("\x60")

        opening = { marker: match[1][0], length: match[1].length, line: number, fence: match[1] }
      end
    end
    opening
  end

end
