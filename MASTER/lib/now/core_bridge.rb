# frozen_string_literal: true

require_relative "../../core/master"

module Master
  module Now
    # CoreBridge — run one coding goal through the core Fold from inside the
    # interactive CLI. The Fold (core/) is the runtime this rebuild is folding
    # toward; the bridge routes a single goal to it while the legacy pipeline still
    # handles everything else, so the cutover stays incremental and always green.
    #
    # Turns stream to the event bus as they happen, so the terminal and the web
    # dashboard see the same live trace they get from the legacy path.
    module CoreBridge
      module_function

      def run(goal, root:, bus: nil, model: nil, model_id: nil, max_turns: 40, on_turn: nil)
        transcript = []
        observer = lambda do |turn:, effect:, observation:|
          line = "#{turn}: #{effect} -> #{observation}"
          transcript << line
          bus&.publish("core:turn", turn:, effect: effect.to_s, ok: observation.ok?, detail: observation.message)
          on_turn&.call(line)
        end

        done = Master::Core::Fold.new(
          model:       model || Master::Core::Model.new(**{ model_id: }.compact),
          constitution: Master::Core::Constitution.load(data_dir: Master.data_path),
          world:       Master::Core::World.new(root:),
          memory:      Master::Core::Memory.new,
          max_turns:,
          observer:
        ).run(goal)

        { reason: done.reason, turns: done.turns, summary: done.summary, transcript: }
      end

      def run_string(goal, root:, bus: nil, model: nil, model_id: nil)
        return "core: no goal" if goal.to_s.strip.empty?
        # An injected model (tests) runs offline; a real one needs a provider key.
        return Master.no_api_key_message if model.nil? && !Master.any_api_key_present?

        result = run(goal, root:, bus:, model:, model_id:)
        header = "core: #{result[:reason]} turns=#{result[:turns]}"
        [header, *result[:transcript], result[:summary]].compact.join("\n")
      end
    end
  end
end
