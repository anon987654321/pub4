# frozen_string_literal: true

module Master::Core
  # Proof — what has been shown, and what must be shown before `done`.
  #
  # The seventh concept in the fold, and the first raise of `core_files` since
  # the spine was written. It came out of Memory, which was three objects wearing
  # one name: a transcript, an evidence ledger, and the risk gates. That is why
  # it measured 16 public methods against ABSTRACTION's 10 — not an idiom this
  # time, the way Constitution's class methods were, but the count telling the
  # truth about the design.
  #
  # The seam is where the Constitution looks. Every rule that can refuse a `done`
  # effect asks this object and nothing else: proved?, council_required?,
  # council_cleared?, ideation_satisfied?. Memory answers what was said; Proof
  # answers whether it was enough.
  class Proof
    # What counts as proof, and how much of it ends the turn. This is the one
    # Ruby source for the core's evidence policy; the Model's prompt is built
    # from it (no restated numbers) and a test pins it to data/rules.yml, whose
    # evidence_scoring the lib spine still reads until that spine is severed.
    SCORING = { test_pass: 35, scan_clean: 25, code_review: 20, log_analysis: 10, profiling_data: 10 }.freeze
    PASS_THRESHOLD = 80
    ALTERNATIVES_REQUIRED = 15

    attr_reader :risk

    def initialize(risk: :low)
      @risk = risk.to_sym
      @evidence = []
      @ideation_complete = false
      @council_pass = false
      @write_trees = []
      @write_lines = 0
      @read_paths = []
      @asked = false
      @started_at = Time.now
    end

    def council_required? = %i[high critical].include?(@risk)
    def council_cleared? = @council_pass || !council_required?
    def ideation_satisfied? = !ideation_required? || @ideation_complete
    def proved? = evidence_score >= PASS_THRESHOLD

    def mark_ideation_complete!(approaches: nil)
      tap { @ideation_complete = approaches.nil? || approaches.to_i >= ALTERNATIVES_REQUIRED }
    end

    def scope
      { trees: @write_trees.dup, elapsed_s: Time.now - @started_at, write_lines: @write_lines,
        read_paths: @read_paths.dup, asked: @asked }
    end

    def mark_council_pass!(detail: "council pass")
      @council_pass = true
      @evidence << Evidence.new(kind: :council_pass, ok: true, score: 0, detail:, at: Time.now.utc)
      self
    end

    def record_evidence(effect, observation)
      remember_write(effect) if effect.verb == :write
      remember_read(effect) if effect.verb == :read && observation.ok?
      @asked = true if effect.verb == :ask && observation.ok?
      return unless effect.verb == :exec && observation.ok?

      kind = effect.args[:evidence].to_s.to_sym
      score = SCORING.fetch(kind, 0)
      @evidence << Evidence.new(kind:, ok: true, score:, detail: observation.message, at: Time.now.utc) if score.positive?
    end

    private

    # Both are asked only by the two predicates above. Public here would put the
    # count back where this split started.
    def ideation_required? = %i[medium high critical].include?(@risk)
    def evidence_score = @evidence.select(&:ok).sum(&:score)

    def remember_write(effect)
      tree = effect.args[:path].to_s.split("/").find { |part| Constitution::REPO_TREES.include?(part) }
      @write_trees << tree if tree
      @write_lines += effect.args[:content].to_s.lines.size
    end

    def remember_read(effect)
      @read_paths << effect.args[:path].to_s
    end
  end
end
