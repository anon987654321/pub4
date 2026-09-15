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
        observer = build_turn_observer(transcript, root:, bus:, on_turn:)

        memory ||= Master::Core::Memory.new(risk:)
        critique_runner = container ? CouncilCrit.runner_for(container) : nil
        world = Master::Core::World.new(root:, critique_runner:, undo: container&.fetch(:undo, nil))

        model ||= Master::Core::Model.new(**{ model_id:, chat: agent_chat(container, bus:) }.compact)
        done = build_fold(model:, memory:, world:, max_turns:, observer:).run(goal)

        { reason: done.reason, turns: done.turns, summary: done.summary, transcript:, risk: memory.proof.risk }
      end

      # Core::Model speaks RubyLLM's chat shape and, left alone, calls RubyLLM
      # itself. The agent's dispatcher is the door every other call passes:
      # MASTER_MODEL, ollama, the circuit breaker, the failover hop and the cost
      # ledger all live there, and a fold that went round it had none of them —
      # forced to a local model, it still asked OpenRouter and died on a 503.
      #
      # Every model is asked the same way: one schema, temperature 0. The fold
      # behaves alike whichever model answers, and each tier enforces the
      # schema as far as it can. The reply's `why` is the model's reason for the
      # effect, and the bus carries it to the operator before the effect runs.
      AgentChat = Struct.new(:agent, :bus, :system) do
        def with_instructions(text) = AgentChat.new(agent, bus, text)

        def ask(prompt)
          reply = agent.ask_once(prompt, system:, law: false, temperature: 0, format: Master::Core::Model::SCHEMA)
          why = CoreBridge.reason_in(reply)
          bus&.publish("core:reason", why:) if why
          Reply.new(reply)
        end
      end
      Reply = Struct.new(:content)

      # Read the way Core::Model.parse reads the object: first brace to last.
      def reason_in(reply)
        json = reply.to_s.gsub(/```[a-z]*/i, "")[/\{.*\}/m]
        why = json && JSON.parse(json)["why"].to_s.strip
        why unless why.to_s.empty?
      rescue JSON::ParserError, TypeError => e
        # No reason is a reply without one, not a failed turn: Model.parse
        # reports the malformed object itself.
        Master::Ground::Swallow.log(e, context: "CoreBridge.reason_in")
      end

      def agent_chat(container, bus:)
        agent = container && container[:agent]
        AgentChat.new(agent, bus) if agent.respond_to?(:ask_once)
      end

      # The Fold writes through World rather than the Io tools, so the turn's
      # WriteTracker hears of a write only from here.
      def build_turn_observer(transcript, root:, bus:, on_turn:)
        lambda do |turn:, effect:, observation:|
          line = "#{turn}: #{effect} -> #{observation}"
          transcript << line
          if effect.verb == :write && observation.ok?
            Master::Trace::WriteTracker.current&.record(File.expand_path(effect.args[:path].to_s, root))
          end
          bus&.publish("core:turn", turn:, effect: effect.to_s, verb: effect.verb, subject: effect_subject(effect),
                                    ok: observation.ok?, detail: observation.message)
          on_turn&.call(line)
        end
      end

      # The part of an effect a person names it by: the file, the command, the
      # question. Written content stays out; it is the payload.
      def effect_subject(effect)
        args = effect.args
        case effect.verb
        when :exec then Array(args[:argv]).join(" ")
        when :git then [args[:operation], *Array(args[:paths])].join(" ")
        else (args[:path] || args[:prompt] || args[:text] || args[:summary] || args[:scope]).to_s
        end
      end

      def build_fold(model:, memory:, world:, max_turns:, observer:)
        Master::Core::Fold.new(
          model:,
          constitution: Master::Core::Constitution.load(data_dir: Master.data_path, verify: scan_verifier,
                                                        sandbox: shell_sandbox),
          world:,
          memory:,
          max_turns:,
          observer:,
        )
      end

      # The Fold writes through World, not through the Io tools, so it needs the
      # same guard handed to it. Handed in as `verify:` rather than required by
      # Constitution, because a require puts lib/review/ inside the fold spine
      # (test_core_no_lib_backedges). Returns the blocking findings as strings.
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
      # Three answers, because the policy has three. :deny returns a reason and
      # blocks. An :ask the policy recognises by name — a push, a hard reset, a
      # deploy — returns { ask: } and the Constitution turns it into a Request a
      # person answers. The :ask it returns for every command it has no pattern
      # for returns nil and proceeds, because that is most commands and the fold
      # has to be able to run its own tests.
      def shell_sandbox
        lambda { |argv|
          decision = Master::Ground::Policy::Sandbox.decide(argv.join(" "))
          next decision.reason if decision.deny?
          next({ ask: decision.reason }) if decision.recognised_ask?

          nil
        }
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
