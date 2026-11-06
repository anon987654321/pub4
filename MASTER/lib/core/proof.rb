# frozen_string_literal: true

require "digest"

module Master::Core
  # Proof — what has been shown, and what must be shown before `done`.
  #
  # The seventh concept in the fold, and the first raise of `core_files` since
  # the spine was written. It came out of Memory, which was three objects wearing
  # one name: a transcript, an evidence ledger, and the risk checks. That is why
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
    # from it (no restated numbers).
    SCORING = { test_pass: 35, scan_clean: 25, code_review: 20, log_analysis: 10, profiling_data: 10 }.freeze
    PASS_THRESHOLD = 80
    ALTERNATIVES_REQUIRED = 15

    # What can actually produce each kind of proof. The kind was whatever the
    # model wrote in the effect, so `exec(["true"], evidence: "test_pass")` was
    # worth 35 points and four such calls ended the turn — the fold graded its own
    # paper. A command that does not run the tests cannot be a passing test run.
    #
    # Unmatched scores nothing rather than blocking: the fold may run whatever it
    # likes, it cannot claim credit for it. Refusing the effect outright
    # would turn a wrong label into a dead turn, and the label is the model's
    # mistake to correct on the next one.
    PRODUCERS = {
      # `ruby ... test/x.rb` rather than `ruby -I<something>test`: the real
      # invocation in this repo is `ruby -Ilib -Itest test/test_core_world.rb`,
      # where the include flags come first and an adjacency pattern misses it.
      test_pass: %r{\b(?:rake\s+test|rails\s+test|rspec|minitest|bin/(?:ci|check)|ruby\S*\s[^;|]*\btest/)},
      scan_clean: %r{\b(?:bin/(?:check|scan)|rubocop|brakeman|bundler-audit|rake\s+(?:lint|audit|scan))},
      code_review: %r{\b(?:bin/(?:review|critique)|rake\s+(?:review|critique))},
      log_analysis: %r{\b(?:journalctl|dmesg|rcctl|/var/log|\.log\b)},
      profiling_data: %r{\b(?:benchmark|stackprof|ruby-prof|memory_profiler|--profile)},
    }.freeze

    RISK_ORDER = %i[low medium high critical].freeze

    attr_reader :risk

    def initialize(risk: :low)
      @risk = risk.to_sym
      @evidence = []
      @ideation_complete = false
      @council_pass = false
      @write_trees = []
      @write_paths = []
      @write_hashes = {}
      @repository_root = nil
      @write_lines = 0
      @read_paths = []
      @asked = false
      @acted = false
      @started_at = Time.now
      @generation = 0
    end

    # A resumed task may retain or escalate its risk, never downgrade it.
    def escalate_risk!(value)
      next_risk = value.to_s.downcase.to_sym
      raise ArgumentError, "unknown risk: #{value}" unless RISK_ORDER.include?(next_risk)

      @risk = next_risk if RISK_ORDER.index(next_risk) > RISK_ORDER.index(@risk)
      self
    end

    def council_required? = %i[high critical].include?(@risk)
    def council_cleared? = @council_pass || !council_required?
    def ideation_satisfied? = !ideation_required? || @ideation_complete
    def proved? = evidence_score >= PASS_THRESHOLD

    # Only a trusted host attaches a repository boundary. Resumed writes are
    # rehydrated only while their persisted digest still matches the live file.
    def authorize_repository_delivery!(root:, written_paths: {})
      @repository_root = File.realpath(root).freeze
      written_paths.each do |path, digest|
        relative = repository_path(path)
        next unless relative && digest.to_s.match?(/\A[0-9a-f]{64}\z/i)

        full = File.join(@repository_root, relative)
        next unless File.file?(full) && !File.symlink?(full)
        next unless Digest::SHA256.file(full).hexdigest == digest.to_s

        @write_hashes[relative] = digest.to_s
        @write_paths << relative unless @write_paths.include?(relative)
      end
      self
    end

    # The Constitution attaches these trusted digests to the exact commit
    # effect. A changed, missing or unowned path has no commit receipt.
    def repository_commit_hashes(paths)
      return unless @repository_root && proved?

      requested = Array(paths).map { |path| repository_path(path) }
      return if requested.empty? || requested.any?(&:nil?) || requested.uniq.size != requested.size

      requested.each_with_object({}) do |path, result|
        digest = @write_hashes[path]
        full = File.join(@repository_root, path)
        return unless digest && File.file?(full) && !File.symlink?(full)
        return unless Digest::SHA256.file(full).hexdigest == digest

        result[path] = digest
      end
    rescue SystemCallError, ArgumentError
      nil
    end

    # A fold that wrote nothing and ran no mutating command changed nothing, so
    # its `done` claims no state of the tree; it can answer from what it read or
    # observed through a policy-approved read-only probe. The threshold proves
    # changed code, and a commit still needs that proof.
    def answered_from_reads? = @generation.zero? && !@acted && @read_paths.any?

    def mark_ideation_complete!(approaches: nil)
      tap { @ideation_complete = approaches.nil? || approaches.to_i >= ALTERNATIVES_REQUIRED }
    end

    # writable and cleared are the preconditions the Model reads to leave write
    # and done out of the reply schema, so the offer and the check ask one object.
    def scope
      { trees: @write_trees.dup, elapsed_s: Time.now - @started_at, write_lines: @write_lines,
        read_paths: @read_paths.dup, write_paths: @write_paths.uniq, asked: @asked, evidence: evidence_score, proved: proved?,
        answerable: answered_from_reads?, writable: ideation_satisfied?, cleared: council_cleared?,
        repository_delivery: !@repository_root.nil?, delivery_paths: @write_hashes.keys.sort }
    end

    def mark_council_pass!(detail: "council pass")
      @council_pass = true
      @evidence << Evidence.new(kind: :council_pass, ok: true, score: 0, detail:, at: Time.now.utc,
                                generation: @generation)
      self
    end

    # A write the Constitution refused changed no tree, so it starts no new
    # generation: counting it voided the evidence and the read-only answer of a
    # fold whose only write was the one it was stopped from making.
    def record_evidence(effect, observation)
      remember_write(effect) if effect.verb == :write && observation.ok?
      remember_commit(effect) if effect.verb == :git && effect.args[:operation].to_s.to_sym == :commit && observation.ok?
      remember_read(effect) if effect.verb == :read && observation.ok?
      remember_probe(effect) if effect.verb == :probe && observation.message.to_s.start_with?("probe result:")
      invalidate_after_unlabelled_exec(effect) if effect.verb == :exec && observation.ok?
      @asked = true if effect.verb == :ask && observation.ok?
      @acted = true if %i[exec git].include?(effect.verb)
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
    # The third narrowing is not here: whether the kind is earned at all is
    # PRODUCERS' job, checked in record_evidence before anything reaches this
    # sum. By the time a score is added up it is already a kind some command
    # capable of producing it actually produced.
    def evidence_score
      @evidence.select { |e| e.ok && e.generation == @generation }
               .group_by(&:kind)
               .sum { |_kind, found| found.map(&:score).max }
    end

    # An unlabeled exec is an effect whose reach is not known to Proof.
    # Invalidate earlier evidence before the next done decision. Evidence
    # producer execs are observational by contract and retain the generation
    # they are proving.
    def invalidate_after_unlabelled_exec(effect)
      return unless effect.args[:evidence].to_s.empty?

      @generation += 1
    end

    def remember_write(effect)
      @generation += 1
      tree = effect.args[:path].to_s.split("/").find { |part| Constitution::REPO_TREES.include?(part) }
      @write_trees << tree if tree
      path = repository_path(effect.args[:path])
      @write_paths << (path || effect.args[:path].to_s)
      @write_hashes[path] = Digest::SHA256.hexdigest(effect.args[:content].to_s) if @repository_root && path
      @write_lines += effect.args[:content].to_s.lines.size
    end

    def remember_commit(effect)
      expected = effect.args[:expected_hashes].is_a?(Hash) ? effect.args[:expected_hashes] : {}
      expected.each do |path, digest|
        key = repository_path(path)
        @write_hashes.delete(key) if key && @write_hashes[key] == digest.to_s
      end
    end

    def repository_path(value)
      text = value.to_s
      return if text.empty? || text.include?("\0") || text.split(%r{[\\/]}).include?("..")
      return text.delete_prefix("./") unless @repository_root

      full = File.expand_path(text, @repository_root)
      return unless full.start_with?(@repository_root + File::SEPARATOR)

      relative = full.delete_prefix(@repository_root + File::SEPARATOR).tr(File::SEPARATOR, "/")
      return if relative.split("/").include?(".git")

      relative
    rescue ArgumentError
      nil
    end

    def remember_read(effect)
      @read_paths << effect.args[:path].to_s
    end

    # A policy-approved probe is observation, not an edit or test-pass claim.
    # Its exit status stays visible to the model, but it earns no evidence points.
    def remember_probe(effect)
      @read_paths << "probe: #{Array(effect.args[:argv]).join(" ")}"
    end
  end
end
