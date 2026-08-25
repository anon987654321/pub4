# frozen_string_literal: true

module Master
  module CLI
    # CoreBridge — run one coding goal through the core Fold from the CLI and web
    # cutover. Folds agent turns; slash commands use command_registry directly.
    #
    # Turns stream to the event bus as they happen, so the terminal and the web
    # dashboard see the same live trace they get from the legacy path.
    module CoreBridge
      module_function

      def run(goal, root:, bus: nil, model: nil, model_id: nil, max_turns: 40, on_turn: nil, memory: nil,
              container: nil, risk: :low)
        transcript = []
        observer = build_turn_observer(transcript, bus:, on_turn:)

        memory ||= Master::Core::Memory.new(risk:)
        critique_runner = container ? CouncilCrit.runner_for(container) : nil

        done = build_fold(root:, model:, model_id:, memory:, critique_runner:, max_turns:, observer:).run(goal)

        { reason: done.reason, turns: done.turns, summary: done.summary, transcript:, risk: memory.proof.risk }
      end

      def build_turn_observer(transcript, bus:, on_turn:)
        lambda do |turn:, effect:, observation:|
          line = "#{turn}: #{effect} -> #{observation}"
          transcript << line
          bus&.publish("core:turn", turn:, effect: effect.to_s, ok: observation.ok?, detail: observation.message)
          on_turn&.call(line)
        end
      end

      def build_fold(root:, model:, model_id:, memory:, critique_runner:, max_turns:, observer:)
        Master::Core::Fold.new(
          model:       model || Master::Core::Model.new(**{ model_id: }.compact),
          constitution: Master::Core::Constitution.load(data_dir: Master.data_path, verify: scan_verifier,
                                                        sandbox: shell_sandbox),
          world:       Master::Core::World.new(root:, critique_runner:),
          memory:,
          max_turns:,
          observer:,
        )
      end

      # The Fold writes through World, not through the Io tools, so it needs the
      # same guard handed to it. Returns the blocking findings as strings.
      def scan_verifier
        lambda do |path:, content:|
          Master::Review::Scan::WriteGuard.default.verdict(path:, content:).blocking
                                          .map { |f| "#{f[:rule]}:#{f[:line]} #{f[:message]}" }
        end
      end

      # And the Fold EXECS through World, not through Io::Shell — the same
      # sentence, one verb over. Io::Shell has consulted Ground::Policy::Sandbox
      # since that gate was wired in, so the hardened policy was live on the tool
      # path and absent from the constitutional one, which is the path that runs
      # unattended. Handed in rather than required, because core reaches nothing
      # in lib/ (test_no_lib_backedges).
      #
      # Returns a reason only for :deny. The policy answers :ask for anything it
      # does not recognise, which is most commands, and Io::Shell does not treat
      # that as an error either — mapping it to one here would refuse the fold its
      # own test runs.
      def shell_sandbox
        ->(argv) { Master::Ground::Policy::Sandbox.decide(argv.join(" ")).then { |v| v.reason if v.deny? } }
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
