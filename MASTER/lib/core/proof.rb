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

    # What can actually produce each kind of proof. The kind was whatever the
    # model wrote in the effect, so `exec(["true"], evidence: "test_pass")` was
    # worth 35 points and four such calls ended the turn — the fold graded its own
    # paper. A command that does not run the tests cannot be a passing test run.
    #
    # Unmatched scores nothing rather than blocking: the fold may run whatever it
    # likes, it just cannot claim credit for it. Refusing the effect outright
    # would turn a wrong label into a dead turn, and the label is the model's
    # mistake to correct on the next one.
    PRODUCERS = {
      # `ruby ... test/x.rb` rather than `ruby -I<something>test`: the real
      # invocation in this repo is `ruby -Ilib -Itest test/core/test_world.rb`,
      # where the include flags come first and an adjacency pattern misses it.
      test_pass: %r{\b(?:rake\s+test|rails\s+test|rspec|minitest|bin/(?:ci|check|gate)|ruby\S*\s[^;|]*\btest/)},
      scan_clean: %r{\b(?:bin/(?:check|gate|scan)|rubocop|brakeman|bundler-audit|rake\s+(?:lint|audit|scan))},
      code_review: %r{\b(?:bin/(?:review|critique)|rake\s+(?:review|critique))},
      log_analysis: %r{\b(?:journalctl|dmesg|rcctl|/var/log|\.log\b)},
      profiling_data: %r{\b(?:benchmark|stackprof|ruby-prof|memory_profiler|--profile)},
    }.freeze

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
      @generation = 0
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
      @evidence << Evidence.new(kind: :council_pass, ok: true, score: 0, detail:, at: Time.now.utc,
                                generation: @generation)
      self
    end

    def record_evidence(effect, observation)
      remember_write(effect) if effect.verb == :write
      remember_read(effect) if effect.verb == :read && observation.ok?
      @asked = true if effect.verb == :ask && observation.ok?
      return unless effect.verb == :exec && observation.ok?

      kind = effect.args[:evidence].to_s.to_sym
      score = SCORING.fetch(kind, 0)
      return unless score.positive? && PRODUCERS[kind]&.match?(Array(effect.args[:argv]).join(" "))

      @evidence << Evidence.new(kind:, ok: true, score:, detail: observation.message, at: Time.now.utc,
                                generation: @generation)
    end

    private

    # Both are asked only by the two predicates above. Public here would put the
    # count back where this split started.
    def ideation_required? = %i[medium high critical].include?(@risk)

    # Two narrowings, both of which the old sum allowed.
    #
    # Only the CURRENT generation counts. Evidence proved something about the code
    # as it stood when it was earned; a write since then makes it a claim about a
    # tree that no longer exists. The old sum let a fold test, then rewrite the
    # file it had tested, then reach `done` on the strength of the earlier run.
    #
    # And each kind scores ONCE. Nothing deduplicated, so three `test_pass` tags
    # were 105 points from a single kind of proof — the threshold exists to demand
    # several independent kinds, and repetition is not independence.
    #
    # What this deliberately does NOT fix: the kind is still whatever the model
    # labelled the exec with, so `exec(["true"], evidence: "test_pass")` still
    # scores 35. Binding a kind to the commands that can legitimately produce it
    # is the real answer and is a policy table, not a one-line predicate.
    def evidence_score
      @evidence.select { |e| e.ok && e.generation == @generation }
               .group_by(&:kind)
               .sum { |_kind, found| found.map(&:score).max }
    end

    def remember_write(effect)
      @generation += 1
      tree = effect.args[:path].to_s.split("/").find { |part| Constitution::REPO_TREES.include?(part) }
      @write_trees << tree if tree
      @write_lines += effect.args[:content].to_s.lines.size
    end

    def remember_read(effect)
      @read_paths << effect.args[:path].to_s
    end
  end
end
