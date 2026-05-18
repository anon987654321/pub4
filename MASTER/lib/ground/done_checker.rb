# frozen_string_literal: true

module Master
  module Ground
  class DoneChecker
    REQUIRED_KEYS = %i[files symbols callers].freeze

    def initialize(root: Master::ROOT, verifier: PatchVerifier.new(root: root))
      @root = root
      @verifier = verifier
    end

    def call(plan)
      normalized = normalize(plan)
      checks = @verifier.verify(
        files: normalized.fetch(:files),
        symbols: normalized.fetch(:symbols),
        references: normalized.fetch(:callers)
      )
      {
        done: @verifier.ok?(checks),
        checks: checks,
        report: @verifier.report(checks),
        missing_plan_keys: REQUIRED_KEYS - normalized.keys
      }
    end

    def self.done?(plan, root: Master::ROOT)
      new(root: root).call(plan).fetch(:done)
    end

    private

    def normalize(plan)
      hash = plan.respond_to?(:to_h) ? plan.to_h : {}
      {
        files: Array(hash[:files] || hash["files"]),
        symbols: Array(hash[:symbols] || hash["symbols"]),
        callers: hash[:callers] || hash["callers"] || {}
      }
    end
  end
  end
end
