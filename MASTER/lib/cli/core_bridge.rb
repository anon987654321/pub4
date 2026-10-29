# frozen_string_literal: true

require_relative "../design/authoring"
require_relative "../trace/effect_observer"

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
              container: nil, risk: :low, mode: nil, allowed_tools: nil, cancellation: nil)
        cancellation.activate! if cancellation&.respond_to?(:activate!)
        workspace_root = workspace_root_for(root)
        lifecycle_bus = lifecycle_event_bus(bus:, requested_root: root, workspace_root:)
        transcript = []
        observer = build_turn_observer(transcript, root: workspace_root, bus:, on_turn:)

        memory ||= Master::Core::Memory.new(risk:)
        model ||= Master::Core::Model.new(**{ model_id:, chat: agent_chat(container, bus:) }.compact)
        requested_mode = mode ? Master::Operator::Mode.for(mode) : :repair
        mission = start_mission(
          goal,
          root:,
          bus:,
          model: model_id || model,
          mode: requested_mode,
          risk:,
          intent: Master::CLI::IntentRouter.new.classify(goal),
        )
        seed_continuation(memory, mission.record)
        seed_design_brief(memory, goal, mission.record, root:)
        begin
          mission.transition!(
            :plan,
            plan: Master::Ground::ActivePlan.read(root) || "fold plan: constitutional turn loop",
          )
          operator_mode = Master::Operator::Mode.for(mission.record.dig("operator", "mode") || requested_mode)
          mode_spec = Master::Operator::Mode.spec(operator_mode)
          capabilities = Master::Operator::Mode.capabilities(operator_mode)
          capabilities = grant_tools(capabilities, allowed_tools) unless allowed_tools.nil?
          bus&.publish(
            "operator:mode",
            mode: requested_mode,
            risk: mission.record.dig("operator", "risk") || mode_spec[:risk],
            model_tier: mode_spec[:model_tier],
            council_required: mode_spec[:council],
          )
          world = build_world(root: workspace_root, container:, capabilities:, network: network_client(container))
          mission.transition!(:execute)
          effect_observer = build_effect_observer(
            bus: lifecycle_bus, mission_id: mission.id, attempt_id: mission_attempt_id(mission),
          )
          done = build_fold(root: workspace_root, model:, memory:, world:, max_turns:, observer:, effect_observer:, capabilities:, cancellation:).run(goal)
          unless %i[cancelled trace_failed needs_user blocked unknown_outcome recovery_failed].include?(done.reason)
            mission.transition!(:verify, summary: continuation_summary(done))
          end
          settle_mission(mission, done)

          { mission: mission.record, reason: done.reason, turns: done.turns, summary: done.summary,
            transcript:, risk: memory.proof.risk }
        rescue StandardError => e
          defer_mission_on_error(mission, e)
          raise
        end
      end

      # The tool names a person already types, as the capabilities the fold holds.
      # A list narrows the mode's profile and never widens it: Capabilities can
      # drop and cannot acquire, so a tool the profile lacks stays refused.
      # Reading is always held; a list that names nothing leaves the fold read-only.
      TOOL_CAPABILITIES = {
        "read" => %i[read], "glob" => %i[read], "grep" => %i[read], "ls" => %i[read],
        "edit" => %i[write], "multiedit" => %i[write], "notebookedit" => %i[write],
        "write" => %i[write create],
        "bash" => %i[execute],
        "webfetch" => %i[network], "websearch" => %i[network]
      }.freeze
      ALWAYS_HELD = %i[stdio read].freeze
      TOOL_ENTRY = /[^\s,()]+(?:\([^)]*\))?/

      # `plan` reads and proposes; every other permission mode runs the repair
      # profile, because the Constitution judges each effect whichever is named.
      def mode_for_permission(value)
        value.to_s == "plan" ? :plan : nil
      end

      # A scoped entry such as Bash(git diff:*) is refused rather than widened to
      # the whole tool: the fold has no per-command grant to give it.
      def grant_tools(capabilities, list)
        granted = []
        list.to_s.scan(TOOL_ENTRY).each do |entry|
          caps = entry.match?(/[()]/) ? nil : TOOL_CAPABILITIES[entry.downcase]
          if caps
            granted.concat(caps)
          else
            Master::Trace::Dmesg.status("cli0", "allowed tool ignored, #{entry}", io: $stderr)
          end
        end
        capabilities.drop(*(capabilities.capabilities - granted - ALWAYS_HELD))
      end

      # Only the interactive session sets an asker; see Session#terminal_ask.
      def build_world(root:, container:, capabilities: Master::Core::Capabilities.for(:fix), network: nil)
        critique_runner = container ? CouncilCrit.runner_for(container) : nil
        Master::Core::World.new(root:, ask: Fiber[:master_terminal_ask], critique_runner:,
                                undo: container&.fetch(:undo, nil), capabilities:, network:)
      end

      # MASTER/ is the runtime's own root; the tree the fold edits is the repository
      # around it. The Constitution and the World both take this one answer, so a
      # relative path means the same file to the check that judges it and the hand that writes it.
      def workspace_root_for(root)
        path = File.expand_path(root)
        path == Master::ROOT ? Master::REPO_ROOT : path
      end

      def network_client(container)
        governor = container&.fetch(:governor, nil)
        return unless governor

        fetcher = Master::Io::WebFetch.new(governor:, event_bus: container[:bus])
        ->(url:) { fetcher.call(url:) }
      end

      def start_mission(goal, root:, bus:, model:, mode:, risk:, intent:)
        checkpoint = lambda do |id:, root:, files:|
          Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints")).create(
            label: "mission-#{id}", files:,
          )
        end
        Master::Fix::Mission.new(root:, bus:, checkpoint:).start_or_resume!(
          goal:, scope: root, model:, effort: ENV.fetch("MASTER_EFFORT", "medium"),
          plan: Master::Ground::ActivePlan.read(root), origin: "fold", auto_continue: true,
          mode:, risk:, intent:
        )
      end

      def defer_mission_on_error(mission, error)
        record = Master::Fix::Mission.current(root: mission.root)
        return unless record && %w[running waiting].include?(record["state"].to_s)

        mission.fail!("#{error.class}: #{error.message}")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CoreBridge.defer_mission_on_error")
      end

      # A frontend mission starts from the design brief the fixer is held to, so the
      # fold plans against the house direction instead of its own habits.
      def seed_design_brief(memory, goal, record, root:)
        return unless record.dig("operator", "intent").to_s == "design_frontend"

        memory.note(:design, Master::Design::Authoring.mission_context(goal:, root:))
      end

      def seed_continuation(memory, record)
        return unless record && record["attempt_count"].to_i > 1

        summary = record["summary"].to_s
        reason = record["wake_reason"].to_s
        memory.note(:continuation, "This is another bounded attempt at the same durable task. Previous attempt: #{summary}. Wake: #{reason}. Re-inspect the current tree; never assume the old state is unchanged.")
      end

      def continuation_summary(done)
        done.summary.to_s.empty? ? "attempt ended: #{done.reason}" : done.summary
      end

      def settle_mission(mission, done)
        if done.reason == :complete
          mission.finish!(state: "completed", summary: done.summary)
        elsif %i[needs_user blocked].include?(done.reason)
          mission.block!(reason: done.summary.to_s)
        elsif done.reason == :trace_failed
          # The effect may already have happened, but its after-record is missing.
          # Preserve ambiguity explicitly; never auto-continue and repeat the effect.
          mission.finish!(state: "unknown_outcome", summary: done.summary)
        elsif %i[cancelled unknown_outcome recovery_failed].include?(done.reason)
          # Explicit stop or an outcome that could not be reconciled is terminal
          # for this attempt. The supervisor must not replay it as a blind retry.
          mission.finish!(state: done.reason.to_s, summary: done.summary)
        else
          mission.defer!(reason: "attempt #{done.reason}: #{continuation_summary(done)}")
        end
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
          if why && bus
            # The reason can echo prompts, source snippets, paths, or secrets. Persist only
            # bounded diagnostic metadata; the local turn still owns the actual reply.
            bus.publish("core:reason", Master::Execution::Contract.diagnostic_fields(why, key: :why))
          end
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
                                    ok: observation.ok?, detail: public_effect_detail(observation),
                                    **public_output_metrics(effect, observation))
          on_turn&.call(line)
        end
      end

      # Always audit even when no host supplied a bus. In that case persist to the
      # relevant runtime root without subscribers; never turn missing UI wiring
      # into an execution-audit bypass.
      def lifecycle_event_bus(bus:, requested_root:, workspace_root:)
        return bus if bus

        requested_root = File.expand_path(requested_root)
        canonical_roots = [Master::ROOT, Master::REPO_ROOT].map { |path| File.expand_path(path) }
        telemetry_root = canonical_roots.include?(requested_root) ? Master::ROOT : workspace_root
        event_log = Master::Trace::Log::Event.new(root: telemetry_root)
        Master::Trace::EventBus.new(event_log:)
      end

      # The lifecycle stream intentionally excludes effect arguments: argv, URLs,
      # prompts and write content may contain secrets or private user data.
      def build_effect_observer(bus:, mission_id: nil, attempt_id: nil)
        Master::Trace::EffectObserver.new(bus:, mission_id:, attempt_id:)
      end

      def mission_attempt_id(mission)
        attempt = [mission.record.fetch("attempt_count", 1).to_i, 1].max
        "#{mission.id}:#{attempt}"
      end

      # The part of an effect a person names it by: the file, the command, the
      # question. Written content stays out; it is the payload.
      # This stream is shared and persisted. Identify the action without copying
      # paths, argv, URLs, prompts, note text, summaries or file contents into it.
      # The full observation remains available on the operator's local transcript.
      def effect_subject(effect)
        case effect.verb
        when :read then "file read"
        when :write then "file write"
        when :exec then "command"
        when :git then "git action"
        when :http then "network request"
        when :ask then "approval request"
        when :note then "note"
        when :critique then "review"
        when :done then "completion"
        else effect.verb.to_s
        end
      end

      def public_effect_detail(observation)
        observation.ok? ? "completed" : "failed"
      end

      # Keep useful speech/dashboard measurements, never the text being measured.
      def public_output_metrics(effect, observation)
        return {} unless %i[read exec].include?(effect.verb)

        output = observation.message.to_s
        { output_bytes: output.bytesize, output_lines: output.lines.size }
      end

      def build_fold(root:, model:, memory:, world:, max_turns:, observer:, effect_observer: nil,
                     capabilities: Master::Core::Capabilities.for(:fix), cancellation: nil)
        Master::Core::Fold.new(
          model:,
          constitution: Master::Core::Constitution.load(data_dir: Master.data_path, workspace_root: root,
                                                        verify: ToolHooks.wrap_verifier(scan_verifier(root:), root:),
                                                        sandbox: ToolHooks.wrap_sandbox(shell_sandbox(root:), root:),
                                                        capabilities:),
          world:,
          memory:,
          max_turns:,
          observer:,
          effect_observer:,
          cancellation:,
        )
      end

      # The Fold writes through World, not through the Io tools, so it needs the
      # same guard handed to it. Handed in as `verify:` rather than required by
      # Constitution, because a require puts lib/review/ inside the fold spine
      # (test_core_no_lib_backedges). Returns the blocking findings as strings.
      #
      # The effect's path is relative to the workspace, so the guard is given the
      # absolute one: it reads the file's current content as the "before" side
      # of the comparison, and a relative path would resolve against the process
      # cwd and compare against the wrong file (or none).
      def scan_verifier(root: nil)
        lambda do |path:, content:|
          path = File.expand_path(path.to_s, root) if root
          Master::Fix::WriteGuard.default.verdict(path:, content:).blocking
                                          .map { |f| "#{f[:law]}:#{f[:line]} #{f[:message]}" }
        end
      end

      # And the Fold EXECS through World, not through Io::Shell — the same
      # sentence, one verb over. Io::Shell has consulted Ground::Policy::Sandbox
      # since that check was wired in, so the hardened policy was live on the tool
      # path and absent from the constitutional one, which is the path that runs
      # unattended. Handed in rather than required, because core reaches nothing
      # in lib/ (test_no_lib_backedges).
      #
      # Scope is checked before policy classification. Policy decides whether
      # a command is safe, needs a person, or is unknown; scope decides whether
      # the argv can explicitly reach outside this workspace at all. Unknown
      # policy does not mean unlimited filesystem authority.
      def shell_sandbox(root:)
        lambda { |argv|
          scope_error = Master::Ground::Policy::Sandbox.scope_violation(argv, root:)
          next scope_error if scope_error

          decision = Master::Ground::Policy::Sandbox.decide(argv.join(" "))
          next decision.reason if decision.deny?
          next({ ask: decision.reason }) if decision.recognised_ask?

          nil
        }
      end

      def run_string(goal, root:, bus: nil, model: nil, model_id: nil)
        return "core: no goal" if goal.to_s.strip.empty?
        # The dispatcher owns lane reachability. A local model or a signed-in CLI
        # can answer without an API key; a blanket preflight here would hide it.
        result = run(goal, root:, bus:, model:, model_id:)
        header = "core: #{result[:reason]} turns=#{result[:turns]}"
        [header, *result[:transcript], result[:summary]].compact.join("\n")
      end
    end
  end
end
