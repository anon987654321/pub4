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
        model ||= Master::Core::Model.new(**{ model_id:, chat: agent_chat(container, bus:) }.compact)
        mission = start_mission(goal, root:, bus:, model: model_id || model)
        begin
          mission.transition!(:plan, plan: Master::Ground::ActivePlan.read(root) || "fold plan: constitutional turn loop")
          world = build_world(root:, container:)
          mission.transition!(:execute)
          done = build_fold(model:, memory:, world:, max_turns:, observer:).run(goal)
          mission.transition!(:verify, summary: done.summary)
          mission.finish!(state: done.reason == :complete ? "completed" : "interrupted", summary: done.summary)

          { mission: mission.record, reason: done.reason, turns: done.turns, summary: done.summary,
            transcript:, risk: memory.proof.risk }
        rescue StandardError => e
          mission.fail!(e)
          raise
        end
      end

      # Only the interactive session sets an asker; see Session#terminal_ask.
      def build_world(root:, container:)
        critique_runner = container ? CouncilCrit.runner_for(container) : nil
        Master::Core::World.new(root:, ask: Fiber[:master_terminal_ask], critique_runner:,
                                undo: container&.fetch(:undo, nil))
      end

      # A mission checkpoints the files it touches before the fold writes them.
      def start_mission(goal, root:, bus:, model:)
        checkpoint = lambda do |id:, root:, files:|
          Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints")).create(
            label: "mission-#{id}", files:,
          )
        end
        Master::Fix::Mission.new(root:, bus:, checkpoint:).start!(
          goal:, scope: root, model:, effort: ENV.fetch("MASTER_EFFORT", "medium"),
          plan: Master::Ground::ActivePlan.read(root)
        )
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
      #
      # The schema is the turn's offer (Core::Model.offer). Core::Model builds a
      # fresh chat each turn, so the ladder is shared by all of them.
      AgentChat = Struct.new(:agent, :bus, :system, :format, :ladder) do
        def with_instructions(text) = AgentChat.new(agent, bus, text, format, ladder)
        def with_format(schema) = AgentChat.new(agent, bus, system, schema, ladder)

        def ask(prompt)
          reply = agent.ask_once(prompt, system:, law: false, temperature: 0,
                                         format: format || Master::Core::Model::SCHEMA, **Hash(ladder&.pinned))
          ladder&.hear(reply)
          why = CoreBridge.reason_in(reply)
          bus&.publish("core:reason", why:) if why
          Reply.new(reply)
        end
      end
      Reply = Struct.new(:content)

      # A local model that cannot hold the fold says so the same way twice: a
      # reply with no object in it, or an object with no verb the fold knows.
      # A refusal arrives as one of those. After STRIKES in a row the fold asks
      # the next larger model this machine runs, and past the largest, the
      # routed cloud lane when the network answers. It climbs and never steps
      # back down within a goal: a model that failed twice in a row on this
      # transcript has shown what it does with it.
      class ModelLadder
        STRIKES = 2
        LOCAL = /\Aollama[:\/]/

        def initialize(agent:, bus: nil, router: nil, online: -> { Master::Ground::BootReceipt.network? })
          @agent = agent
          @bus = bus
          @router = router
          @online = online
          @model = nil
          @strikes = 0
        end

        def pinned = @model ? { model: @model } : {}

        def hear(reply)
          @strikes = unparsed?(reply) ? @strikes + 1 : 0
          climb if @strikes >= STRIKES
        end

        private

        # parse answers a note whose kind is :parse_error, and only for these.
        def unparsed?(reply)
          Master::Core::Model.parse(reply, verbs: Master::Core::VERBS).args[:kind] == :parse_error
        end

        def climb
          current = @model || @agent.model
          @strikes = 0
          higher = larger_local(current) || cloud_lane(current)
          @bus&.publish("core:escalation", from: current, to: higher, strikes: STRIKES)
          @model = higher if higher
        end

        # The smallest pulled model heavier than this one, among those that fit.
        def larger_local(current)
          return unless current.to_s.match?(LOCAL)

          sized = router.local_models.map { |id| [id, router.ollama_size(id.sub(LOCAL, ""))] }
          floor = router.ollama_size(current.to_s.sub(LOCAL, ""))
          sized.select { |_, size| size > floor }.min_by(&:last)&.first
        end

        def cloud_lane(current)
          return unless @online.call

          Array(@agent.candidate_models).find { |id| !id.to_s.match?(LOCAL) && id != current }
        end

        def router
          @router ||= Master::CLI::Routing::ModelRouter.new(config: Master::Ground::Config.new(Master::ROOT))
        end
      end

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
        return unless agent.respond_to?(:ask_once)

        AgentChat.new(agent, bus, nil, nil, ModelLadder.new(agent:, bus:))
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
