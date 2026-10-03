# frozen_string_literal: true

module Master
  module Review
    # Reusable adversarial prompts for the council and operator tools.
    #
    # The point is to make "ask another model what we missed" concrete and
    # repeatable. Each challenge names its evidence target and expected artifact,
    # so a response can become a fixture, a failed mutation, or a bounded change
    # rather than another page of architectural prose.
    module Challenges
      Challenge = Data.define(:id, :target, :artifact, :directive)

      DEFINITIONS = [
        Challenge.new(
          id: :mutation_guidance,
          target: "tests and executable rules",
          artifact: "a smallest source mutation that a relevant test must kill",
          directive: "Design the smallest realistic mutation of the behavior under review. Name the test that must fail; if it would stay green, identify the missing assertion."
        ),
        Challenge.new(
          id: :counterexample_fixture,
          target: "the proposed invariant",
          artifact: "one concrete executable counterexample fixture",
          directive: "Construct one concrete state, input, viewport, dependency failure, or user path that falsifies the proposed invariant. Prefer a minimal fixture over a warning."
        ),
        Challenge.new(
          id: :metamorphic_relation,
          target: "pure or deterministic behavior",
          artifact: "an input transformation plus a relation between outputs",
          directive: "Find an input transformation that should preserve or predictably change the output. State the relation precisely enough for a Ruby test to execute."
        ),
        Challenge.new(
          id: :differential_oracle,
          target: "two implementations or old/new behavior",
          artifact: "a pairwise oracle and the cases where differences are legitimate",
          directive: "Compare the current path with a simpler reference, prior behavior, or alternate implementation. Separate meaningful differences from expected differences and name the evidence."
        ),
        Challenge.new(
          id: :gate_gaming,
          target: "the gate or metric itself",
          artifact: "an attempted false-green input and the gate that should reject it",
          directive: "Try to make the gate pass while violating the contract it claims to enforce. Use the smallest adversarial change and state exactly which check should catch it."
        ),
        Challenge.new(
          id: :abstraction_assassination,
          target: "the design under review",
          artifact: "a deletion or flattening experiment",
          directive: "Delete the mediating abstraction, wrapper, registry, adapter, or indirection mentally. Describe the smallest direct design that preserves observable behavior. Keep the abstraction only when its contract buys something testable."
        ),
        Challenge.new(
          id: :test_deletion,
          target: "the test suite",
          artifact: "one test method whose removal should expose an unprotected contract",
          directive: "Remove one test method mentally. Name the contract that becomes unprotected and the smallest replacement assertion that would preserve it."
        ),
        Challenge.new(
          id: :trace_specification,
          target: "real execution traces",
          artifact: "an invariant mined from an observed trace",
          directive: "Read actual event or dmesg-style traces and infer one stable relationship that can be asserted without depending on narration or timing trivia."
        ),
        Challenge.new(
          id: :historical_regression,
          target: "Git history",
          artifact: "a regression fixture linked to a corrective commit",
          directive: "Mine bug/fix/restore/regression commits. Prefer regressions that already have a human-authored test, and turn the failure mode into a permanent fixture."
        ),
        Challenge.new(
          id: :assumption_compiler,
          target: "unstated design assumptions",
          artifact: "assumption → fixture → invariant → test",
          directive: "Extract one hidden assumption. Compile it into a concrete fixture, one observable invariant, and one executable test. Do not accept 'the model says so' as an oracle."
        ),
        Challenge.new(
          id: :proof_by_deletion,
          target: "new machinery",
          artifact: "the existing primitive that can disappear",
          directive: "For every proposed new layer, name the existing file, method, rule, or dependency that can be removed. If nothing can disappear, classify the proposal as complexity debt until a concrete contract is shown."
        ),
        Challenge.new(
          id: :balance_audit,
          target: "repository topology",
          artifact: "one simplification and one missing-proof opportunity",
          directive: "Find one place that has more mechanism than its observable contract requires and one place whose real behavior is under-tested. Keep the pair evidence-backed and bounded."
        )
      ].freeze

      IDS = DEFINITIONS.map(&:id).freeze

      def self.prompt(scope: :solution, evidence: nil)
        rows = DEFINITIONS.map.with_index(1) do |challenge, index|
          <<~ROW
            #{index}. #{challenge.id}
               target: #{challenge.target}
               required artifact: #{challenge.artifact}
               ask: #{challenge.directive}
          ROW
        end.join

        [
          "MASTER ADVERSARIAL CHALLENGE PACK",
          "Scope: #{scope}",
          "Treat every answer as a hypothesis until its required artifact or evidence exists.",
          "Do not invent defects. Mark each result observed, plausible, or requiring validation.",
          "Prefer deletion, existing primitives, and executable fixtures over new machinery.",
          "",
          "SOLUTION RED-TEAM",
          "Which proposals share the same hidden assumption?",
          "What useful behavior could regress or accidentally disappear?",
          "What is the smallest deletion or existing primitive being overlooked?",
          "What counterexample state, viewport, input, dependency, or user path could invalidate the direction?",
          "When the field optimizes the same dimension, introduce candidates that invert that assumption.",
          "Do not invent failures. Mark each concern as observed, plausible, or requiring validation.",
          "",
          evidence.to_s.empty? ? nil : "CURRENT EVIDENCE\n#{evidence}",
          "",
          rows
        ].compact.join("\n")
      end
    end
  end
end
