# frozen_string_literal: true

module Law
  # Ruby declares what a Law detects and how it reads; its policy comes from
  # the catalogue entry, so the block has no method to declare severity,
  # languages, paths, lifecycle or autofix a second time.
  class Builder
    %i[source scope absent ask practice fix bad good reads_comments].each { |a| define_method(a) { |v| @h[a] = v } }

    def initialize(id)
      @h = {
        id:, scope: :line, law_scope: nil, absent: nil, detect: nil, check: nil, ask: nil, practice: nil,
        reads_comments: false, tags: [], example_path: nil, reads_beyond_file: false, transform: nil,
        detector: nil, proved_by: nil, source: nil, **::Law.catalogue_policy(id)
      }
    end

    # A detector class (a Review::Scan::Detector) for a Law whose detection needs
    # state, a whole walk or a model: the AST and graph laws, the linters, the
    # semantic evaluators. It is this Law's detector and nothing else's.
    def detector(klass) = @h[:detector] = klass

    # The test that proves this Law's detector, for one that cannot prove itself
    # on two fixtures at boot (it reads a repository, runs a linter or asks a model).
    def proved_by(path) = @h[:proved_by] = path

    # The AstFixer transform that repairs this Law's findings, when one does. A
    # transform in AstFixer::DELETING_TRANSFORMS waits for a person (Scanner#deleting_law?).
    def transform(name) = @h[:transform] = name.to_s

    # A check whose findings depend on more than the file's text and path (git
    # history, sibling files) says so, and Scan::FindingCache never replays it.
    def reads_beyond_file(value) = @h[:reads_beyond_file] = value
    def detect(&block) = @h[:detect] = block

    # `check { |text, file| ... }` answers findings, each built by `finding(line:, message:)`.
    def check(&block) = @h[:check] = block

    # The concern a Law belongs to (DESIGN, TYPOGRAPHY, ...): carried on its findings.
    def tags(*names) = @h[:tags] = names.flatten.map(&:to_sym)

    # The path its fixtures are proved at, for a detector that judges only some paths.
    def example_path(path) = @h[:example_path] = path

    # A law can carry more than one enforcement surface without becoming more
    # than one rule. detect is deterministic evidence, ask is semantic evidence,
    # and practice is conduct guidance. Their combination is useful: one law may
    # be cheap to detect mechanically, expensive to understand semantically, and
    # still impose a working discipline on the operator.
    def build
      refuse_shape!
      refuse_missing!
      @h[:bad] = nil unless @h.key?(:bad)
      @h[:good] = nil unless @h.key?(:good)
      @h[:law_scope] = ::Law.catalogue_entry(@h.fetch(:id)).fetch("universal") ? :universal : :domain

      Definition.new(**@h.slice(*MEMBERS)).prove!
    end

    private

    def refuse(reason) = raise(ArgumentError, "#{@h[:id]}: #{reason}")

    def refuse_shape!
      detectors = %i[detect check detector].count { |k| @h[k] }
      refuse "needs detect, check, detector, ask or practice" if detectors.zero? && !@h[:ask] && !@h[:practice]
      refuse "detect, check and detector are three detectors; keep one" if detectors > 1

      unknown_surfaces = Array(@h[:surfaces]) - ASSESSMENT_SURFACES
      refuse "unknown assessment surfaces #{unknown_surfaces.join(', ')}" if unknown_surfaces.any?
    end

    # Named here so a law missing one hears about the law, not Data#initialize.
    # A Law proved by a named test may carry its fixtures there instead.
    def refuse_missing!
      missing = (@h[:proved_by] ? %i[fix] : %i[bad good fix]).reject { |k| @h.key?(k) }
      refuse "missing #{missing.join(', ')}" unless missing.empty?
    end
  end
end
