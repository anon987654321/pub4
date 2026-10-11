# frozen_string_literal: true

require "json"
require_relative "../convergence/receipt"

module Master
  module Fix
    # /fix learns per target from its own terminal states. The loop reads the
    # prior before a run (a target that mostly fails is observed in full, never
    # sampled incrementally) and writes a hashed receipt after it; Cognition::Mind
    # trains only from a receipt whose bytes match. Poor outcomes never weaken
    # verification, they widen what the next attempt looks at.
    module OutcomeLearning
      CANONICAL_TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze

      # Boot wires the already-running cognitive service after restoring its
      # state. Serialized against active attempts so a run sees one reader.
      def wire_cognition(cognition)
        @run_mutex.synchronize { @cognition = cognition }
        self
      end

      private

      def outcome_guidance(target:, incremental:)
        return { incremental:, prediction: nil } unless @cognition

        label = fix_target_label(target)
        prediction = @cognition.predict_outcome(context: "target=#{label}", action: "/fix")
        guarded = incremental && prediction[:status] == :learned &&
                  prediction[:success_probability].to_f < 0.5
        if prediction[:samples].to_i.positive?
          action = guarded ? "full-scope collection after low prior success" : "requested scope retained"
          Master::Trace::Dmesg.status(
            "fix0",
            "outcome prior target=#{label} samples=#{prediction[:samples]} " \
            "success_probability=#{prediction[:success_probability]} action=#{action}",
          )
        end
        { incremental: guarded ? false : incremental, prediction: }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.outcome_guidance", event_bus: @bus)
        { incremental:, prediction: nil }
      end

      def prior_receipt(prediction, target:)
        return unless prediction.is_a?(Hash)

        {
          context: "target=#{target}",
          action: "/fix",
          status: prediction[:status].to_s,
          samples: prediction[:samples].to_i,
          success_probability: prediction[:success_probability].to_f.clamp(0.0, 1.0),
        }
      end

      def fix_target_label(target)
        absolute = File.expand_path(target.to_s, @root)
        return "." if absolute == @root
        return absolute.delete_prefix("#{@root}/") if absolute.start_with?("#{@root}/")

        target.to_s[0, 240]
      end

      # A hashed record only for the canonical four-tree repo: test roots and
      # partial workspaces deliberately leave no learning receipt.
      def write_outcome_receipt(run_id:, target:, state:, result:, convergence: nil)
        return unless CANONICAL_TREES.all? { |tree| File.directory?(File.join(@root, tree)) }

        receipt = Master::Convergence::Receipt.write(
          root: @root,
          command: "/fix",
          state:,
          details: {
            run_id: run_id.to_s,
            target:,
            summary: result.to_s[0, 400],
            convergence:,
            outcome_prior: prior_receipt(@outcome_prior, target:),
          },
        )
        { source: receipt.fetch(:path).delete_prefix("#{@root}/"), sha256: receipt.fetch(:sha256) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.outcome_receipt", event_bus: @bus)
        nil
      end
    end
  end
end
