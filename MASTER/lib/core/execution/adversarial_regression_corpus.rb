# frozen_string_literal: true

module Master::Core::Execution
  # AdversarialRegressionCorpus — an executable ledger of failure cases.
  #
  # Instead of generic benchmarks, MASTER maintains a corpus of real-world
  # failures (regressions). A change is only "correct" if it solves the
  # current goal without re-introducing any failure from the corpus.
  class AdversarialRegressionCorpus
    attr_reader :cases

    def initialize
      @cases = [] # [ { id: "...", task: "...", expected_evidence: "...", failure_signature: "..." } ]
    end

    # Add a failure case from a completed episode.
    def record_failure(episode)
      @cases << {
        id: episode.id,
        task: episode.intent,
        failure_signature: episode.outcome == :failed ? :regression : :simulated,
        evidence_required: episode.verification.map(&:kind).uniq,
      }
    end

    # Verify that current results do not match any known failure signatures.
    def check_for_regressions(current_evidence)
      @cases.each do |c|
        if current_evidence.include?(c[:failure_signature])
          return Master::Result.err("regression detected: #{c[:id]}", category: :validation)
        end
      end
      Master::Result.ok(true)
    end

    def load_from_yaml(path)
      data = Master.load_yaml(path) || []
      @cases = data
    end
  end
end
