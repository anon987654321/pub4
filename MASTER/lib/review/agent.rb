# frozen_string_literal: true

require_relative "llm_dispatcher"
require_relative "consensus"
require_relative "prompt_filter"
require_relative "agent/model_selector"
require_relative "agent/model_override"
require_relative "agent/prompt_builder"
require_relative "agent/fallback_chain"

module Master
  module Review
    class Agent
      include PromptFilter
      include ModelSelector
      include ModelOverride
      include PromptBuilder
      include FallbackChain

      DEFAULT_MESSAGE_WINDOW_SIZE = 40

      Dependencies = Data.define(
        :config, :session, :tools, :circuit_breaker, :cache, :bus,
        :model_router, :reasoning_modes, :memory, :personality,
        :code_index, :context_window, :homeostat
      ) do
        def self.from_kwargs(config:, session:, tools:, circuit_breaker:, cache:,
                             event_bus: nil, model_router: nil, reasoning_modes: nil,
                             memory: nil, personality: nil, code_index: nil,
                             context_window: nil, homeostat: nil)
          new(
            config:, session:, tools:, circuit_breaker:, cache:, bus: event_bus,
            model_router:, reasoning_modes:, memory:, personality:,
            code_index:, context_window:, homeostat:
          )
        end
      end

      def initialize(deps:)
        @deps = deps
        @config, @session, @tools = deps.config, deps.session, deps.tools
        @circuit_breaker, @cache, @bus = deps.circuit_breaker, deps.cache, deps.bus
        @model_router, @reasoning_modes = deps.model_router, deps.reasoning_modes
        @memory, @personality, @code_index = deps.memory, deps.personality, deps.code_index
        @context_window, @homeostat = deps.context_window, deps.homeostat
        @constitution = nil
        @dispatcher = Master::Review::LLMDispatcher.new(deps:, system_prompt: -> { { static: static_prompt, dynamic: dynamic_prompt } })
      end

      def wire_constitution(constitution) = @constitution = constitution

      # The per-model breaker registry. /fix's LlmRouter asks it which models
      # are open before a repair pass, and the council's two callers check it
      # too; without a reader the router raised, and its rescue reported every
      # candidate open, so every repair pass was skipped.
      def circuit_breaker = @circuit_breaker

      # The container holds no router of its own; /model, model completion and
      # the face's Talk reach the pool through the agent that routes with it.
      def model_router = @model_router

      # A bounded, source-backed research call for operator-requested /fix runs.
      # Web tools screen external text through the injection guard; returned text
      # remains evidence, not instructions, and repair validation stays local.
      #
      # The queries and URLs come from the research protocol in data, not from a
      # model, so the guarded web reads they need are approved for the call: with
      # no terminal the Governor refused every one ("non-TTY: cannot prompt"), and
      # with one it would stop an unattended run to ask per page.
      def research_sources(queries:, sources:, max_queries: 2, max_sources: 3, &progress)
        Fiber[:master_protocol_read] = true
        records = []
        query_list = Array(queries).first(max_queries.to_i.clamp(0, 5))
        web = evidence_tool("WebSearch")
        query_list.each_with_index do |query, index|
          label = query.to_s
          progress&.call(event: "started", kind: "search", index: index + 1, total: query_list.size, label:)
          begin
            result = web&.call(query: label)
            if result.respond_to?(:ok?) && result.ok?
              text = result.value!.to_s.strip
              records << {
                "kind" => "search", "label" => label,
                "status" => text.empty? || text == "(no results)" ? "empty" : "ok",
                "text" => text[0, 1_300],
              }
            else
              records << {
                "kind" => "search", "label" => label, "status" => "unavailable",
                "text" => result.respond_to?(:message) ? result.message.to_s[0, 220] : "WebSearch unavailable",
              }
            end
          rescue StandardError => e
            records << {
              "kind" => "search", "label" => label, "status" => "unavailable",
              "text" => "#{e.class}: #{e.message.to_s[0, 200]}",
            }
          ensure
            progress&.call(event: "completed", kind: "search", index: index + 1, total: query_list.size,
                           label:, status: records.last&.fetch("status", "unknown"))
          end
        end

        source_list = Array(sources).first(max_sources.to_i.clamp(0, 6))
        fetcher = evidence_tool("WebFetch")
        source_list.each_with_index do |url, index|
          source_url = url.to_s
          progress&.call(event: "started", kind: "fetch", index: index + 1, total: source_list.size, label: source_url)
          begin
            result = fetcher&.call(url: source_url)
            if result.respond_to?(:ok?) && result.ok?
              text = result.value!.to_s.strip
              records << {
                "kind" => "fetch", "label" => source_url,
                "status" => text.empty? ? "empty" : "ok",
                "text" => text[0, 1_500],
              }
            else
              records << {
                "kind" => "fetch", "label" => source_url, "status" => "unavailable",
                "text" => result.respond_to?(:message) ? result.message.to_s[0, 220] : "WebFetch unavailable",
              }
            end
          rescue StandardError => e
            records << {
              "kind" => "fetch", "label" => source_url, "status" => "unavailable",
              "text" => "#{e.class}: #{e.message.to_s[0, 200]}",
            }
          ensure
            progress&.call(event: "completed", kind: "fetch", index: index + 1, total: source_list.size,
                           label: source_url, status: records.last&.fetch("status", "unknown"))
          end
        end
        records
      ensure
        Fiber[:master_protocol_read] = nil
      end

      def chat(message, image: nil, stream: true, escalation_depth: 0, task_type: nil, &blk)
        compaction = prepare_chat_turn(message)
        return compaction if compaction.is_a?(Master::Result::Err)

        prepare_evidence(message) if prepare_evidence_for?(message, task_type)
        dispatch = prepare_chat_dispatch(message, task_type)

        rate_err = check_rate_limit(dispatch[:selected_model])
        return rate_err if rate_err

        response = dispatch_chat_response(dispatch, stream:, image:, &blk)
        return response if response.is_a?(Master::Result::Err)

        finalize_chat_response(response, message, dispatch:, image:, stream:, escalation_depth:, task_type:, &blk)
      rescue StandardError => chat_error
        record_trajectory!(message:, model: @config.model, outcome: "failed")
        Result.err("agent: #{chat_error.message}", category: :handler_exception)
      end

      def ask(prompt, context: nil, operation: nil, image: nil, temperature: nil)
        messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
        selected_model = operation ? model_for(operation:) : routed_models.first
        result = @dispatcher.send_with_cache(selected_model, messages, stream: false, image:, temperature:)
        result = retry_on_broke_lane(result, selected_model, messages, image:, temperature:, promote: true)
        record_capability_outcome(operation:, selected_model:, result:)
        raise_failure(result)
        result.to_s
      end

      def ask_once(prompt, system: nil, law: true, model: nil, image: nil, temperature: nil, format: nil, failover: true)
        messages = [{ role: "user", content: prompt }]
        chosen = model || self.model
        sys = role_system(system, law:)
        result = @dispatcher.send_with_cache(chosen, messages, system: sys, stream: false, image:, temperature:, format:)
        result = retry_on_broke_lane(result, chosen, messages, system: sys, image:, temperature:, promote: model.nil?) if failover
        raise_failure(result)
        result.to_s
      end

      def consensus
        return @consensus if @consensus && !local_only?

        models = local_only? ? local_consensus_models : nil
        @consensus = Master::Review::Consensus.new(agent: self, event_bus: @bus, models:)
      end

      def call(ctx)
        on_chunk = ctx[:on_chunk]
        task_type = ctx[:task_type]&.to_s
        image = ctx[:image] if ctx.respond_to?(:[]) && ctx.key?(:image)
        @felt_sense = ctx[:felt_sense]
        message = ctx[:message].to_s
        with_task_type(task_type) do
          if on_chunk
            chat(message, image:, stream: true, task_type:) { |chunk| on_chunk.call(chunk) }
          else
            chat(message, image:, task_type:)
          end
        end
      ensure
        @felt_sense = nil
        Fiber[:master_evidence_mode] = nil
        Fiber[:master_evidence_note] = nil
      end

      def wire_context_window(ctx_window)
        @context_window = ctx_window
      end

      private

      def local_only?
        ENV["MASTER_LOCAL_ONLY"] == "1"
      end

      def local_consensus_models
        router = @model_router
        return [] unless router

        models = []
        models.concat(Array(router.local_models)) if router.respond_to?(:local_models)
        models.concat(Array(router.local_server_models)) if router.respond_to?(:local_server_models)
        models.map(&:to_s)
              .reject(&:empty?)
              .reject { |id| id.end_with?(":cloud", "-cloud") }
              .uniq
      end

      # A hop in retry_on_broke_lane answers with the fallback model, not the
      # one routed to; Result::Ok#model (settle's with_model) names whichever
      # one actually produced this result, so recording against selected_model
      # unconditionally would credit or blame the wrong model after a hop.
      def record_capability_outcome(operation:, selected_model:, result:)
        return unless operation && @model_router.respond_to?(:record_capability_outcome)

        effective_model = result.respond_to?(:model) && result.model ? result.model : selected_model
        @model_router.record_capability_outcome(
          model: effective_model, task_type: operation, success: result.is_a?(Master::Result::Ok),
        )
      end

def single_call_failover_categories
  @single_call_failover_categories ||=
    (@model_router.respond_to?(:failover_skip_categories) && @model_router.failover_skip_categories) ||
    SINGLE_CALL_FAILOVER
end

      # Both single-shot doors — ask and ask_once — used to raise on the first
      # broke model. One hop to the claude_code chain head on any category a
      # retry cannot cure; the 2026-08-20 proof runs showed the error-severity
      # rules die in ask (via Attempt) after ask_once was fixed alone.
      def retry_on_broke_lane(result, chosen, messages, system: nil, image: nil, temperature: nil, promote: true)
        return result unless result.is_a?(Master::Result::Err)

        last = result
        attempted = [chosen]
        park_failed_single_call(chosen, last)
        loop do
          # A lane LaneState refuses (silent, dead, parked, spent) refuses every
          # hop, so walking it would only publish one failover event per model.
          fallback = single_call_fallback_models.reject do |model|
            attempted.include?(model) || !Io::LaneState.usable?(model)
          end.first
          break unless fallback

          attempted << fallback
          @bus&.publish("llm:ask_failover", from: chosen, to: fallback, category: last.category)
          hopped = @dispatcher.send_with_cache(fallback, messages, system:, stream: false, image:, temperature:)
          return record_single_call_substitution(chosen, fallback, hopped, promote:) if hopped.is_a?(Master::Result::Ok)

          last = hopped
          park_failed_single_call(fallback, last)
          break unless last.is_a?(Master::Result::Err)
        end

        offline_when_exhausted(last, chosen)
      end

      # A failed one-shot call parks that model for the bounded cache TTL, so
      # the next request does not repeat the same known failure immediately.
      def park_failed_single_call(model, result)
        return unless result.is_a?(Master::Result::Err)

        category = { budget: :quota_exceeded, exhausted: :quota_exceeded, offline: :timeout }.fetch(result.category, result.category)
        Io::ModelSkipCache.skip!(model, reason: result.message, category:)
      end

      # No lane answers: a typed Offline, which every rescue StandardError around a
      # model call already treats as "no model work this pass".
      def raise_failure(result)
        return unless result.is_a?(Master::Result::Err)
        raise Master::Io::LaneHealth::Offline.new(result.message, gap: result.gap) if result.category == :offline

        raise StandardError, result.message
      end

      # Every candidate dead is one condition with one line, not the last lane's error.
      def offline_when_exhausted(last, chosen)
        models = [chosen, *single_call_fallback_models].uniq
        # Down lanes only: a model parked by its own failure answers with that
        # failure, which says more than "offline".
        down = ->(model) { !Io::LaneState.usable?(model, sources: Io::LaneState::DOWN) }
        return last unless last.category == :offline || models.all?(&down)

        offline = Master::Io::LaneHealth.offline_error(models, refuses: down)
        Master::Trace::Dmesg.once("llm0-offline", offline.message)
        Master::Result.err(offline.message, category: :offline, gap: offline.gap)
      end

      def single_call_fallback_models
        return [] unless @model_router.respond_to?(:fallback_chain)

        task_type = @config.task_type.to_s.empty? ? :exploration : @config.task_type.to_sym
        Array(@model_router.fallback_chain(task_type:)).uniq
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Agent.single_call_fallback_models")
        []
      end

      def record_single_call_substitution(from, to, result, promote: true)
        if result.is_a?(Master::Result::Ok)
          promote_runtime_model(from:, to:) if promote
          Io::QuotaCheck.substituted(from:, to:)
        end
        result
      end

      def dispatch_chat_response(dispatch, stream:, image:, &blk)
        response = attempt_chat_with_fallbacks(candidate_models: dispatch[:candidate_models], prompt: dispatch[:prompt],
          context: dispatch[:context], stream:, image:, &blk)
        @deps.homeostat&.observe(response.is_a?(Master::Result::Err) ? :llm_failure : :llm_success)
        response
      end

      def finalize_chat_response(response, message, dispatch:, image:, stream:, escalation_depth:, task_type:, &blk)
        response = maybe_escalate(response, message, stream:, escalation_depth:, &blk)

        text = response.to_s
        recovery_result = handle_phantom_recovery(text, message:, image:, stream:, escalation_depth:, task_type:, &blk)
        return recovery_result if recovery_result

        @session.add_message(role: :assistant, content: text)
        answered = (response.model if response.respond_to?(:model)) || dispatch[:selected_model]
        record_trajectory!(message:, model: answered, outcome: "complete")
        publish_ctx_footer(answered)
        Result::Ok.new(text, answered)
      end

      # A hard compaction that failed leaves the window at 90% or more, and a
      # turn sent over it is cut off by the provider or silently truncated, so
      # the turn is refused with the compaction's error instead.
      def prepare_chat_turn(message)
        compaction = @context_window&.check_and_compact!
        return compaction if compaction.is_a?(Master::Result::Err)

        @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
        Fiber[:master_tool_streak] = nil
        Fiber[:master_tree_seen] = nil
        Fiber[:master_trajectory_events] = []
        @memory&.auto_save(message) if @memory&.respond_to?(:auto_save)
        @session.add_message(role: :user, content: message)
        observe_preference_feedback(message)
      end

      # Observation is a bounded, opt-in post-ingest hook. A broken preference
      # store must not fail the conversation, and raw user text is never logged.
      def observe_preference_feedback(message)
        return if Fiber[:master_visitor] == true
        return unless defined?(Master::Device::OwnerPreferences)

        root = @config["root"] || Master::ROOT
        result = Master::Device::OwnerPreferences.observe_feedback(
          root:, subject: Fiber[:master_pair_subject], message:,
        )
        return unless result.is_a?(Hash) && result["status"] == "staged"

        @bus&.publish(
          "preferences:suggestion_staged",
          suggestion_id: result["suggestion_id"],
          evidence_count: result["count"],
        )
      rescue StandardError => e
        @bus&.publish("preferences:observation_unavailable", error: e.class.name)
        nil
      end

      # Plain chat stays lightweight, but an explicit request for current facts,
      # research, or a website still must receive its evidence route. The task_type
      # label describes presentation; it must not turn off browser selection.
      def prepare_evidence_for?(message, task_type)
        return true unless task_type.to_s == "chat"

        !%i[conversation unknown].include?(Ground::EvidenceRouter.classify(message))
      end

      def prepare_evidence(message)
        mode = Ground::EvidenceRouter.classify(message)
        Fiber[:master_evidence_mode] = mode
        note = Ground::EvidenceRouter.prompt_for(mode)
        evidence = evidence_preflight(message, mode)
        Fiber[:master_evidence_note] = [note, evidence].compact.join("\n\n")
        @bus&.publish("evidence:routed", mode:, web_required: Ground::EvidenceRouter.web_required?(mode))
      end

      # A turn that needed the web and got nothing must not read as researched.
      LOOKUP_UNAVAILABLE = "Web lookup returned nothing this turn (no search tool, or no result). Say so plainly, " \
                           "answer from what you know if you can, and cite no source you did not read."

      def evidence_preflight(message, mode)
        if mode == :browser
          return unless message.to_s.match?(Ground::EvidenceRouter::SOCIAL_ACCOUNTS)

          return capability_preflight("social_browser", "status")
        end
        return capability_preflight("air_superiority", "scan") if mode == :device
        return if %i[repository conversation opinion].include?(mode)

        local = evidence_tool("SearchKnowledge")&.call(query: message.to_s)
        local_text = local.respond_to?(:ok?) && local.ok? ? local.value!.to_s : ""
        return "Local knowledge:\n#{local_text[0, 4_000]}" if mode == :unknown && !local_text.empty? && local_text != "(no results)"

        snippets = web_snippets(message, mode)
        return LOOKUP_UNAVAILABLE if snippets.empty? && Ground::EvidenceRouter.web_required?(mode)
        return if snippets.empty? && local_text.empty?

        parts = []
        parts << "Local knowledge:\n#{local_text[0, 3_000]}" unless local_text.empty?
        parts << "Web research:\n#{snippets.join("\n\n")[0, 6_000]}" unless snippets.empty?
        parts.join("\n\n")
      end

      # Deep research also asks for the official documentation. Direct references
      # to a research surface use its specialized adapter so the evidence arrives
      # in the shape that surface actually provides.
      def web_snippets(message, mode)
        text = message.to_s
        snippets = []

        if (source = specialized_web_source(text))
          result = source.call(**specialized_web_args(text))
          snippets << result.value!.to_s if result.respond_to?(:ok?) && result.ok?
        end

        web = evidence_tool("WebSearch")
        # External searches need the question's evidence topic, not the intimate
        # details that motivated it. The router leaves technical research intact.
        query = Ground::EvidenceRouter.web_search_query(text)
        searches = [query]
        searches << "#{query} official documentation" if mode == :deep_research
        snippets.concat(
          searches.filter_map do |query|
            result = web&.call(query:)
            result.value!.to_s if result.respond_to?(:ok?) && result.ok?
          end,
        )
        snippets
      end

      def specialized_web_source(message)
        return evidence_tool("CodePen") if message.match?(/codepen\.io|\bcodepen\b/i)
        return evidence_tool("Gist") if message.match?(/gist\.github\.com/i)
        return evidence_tool("YoutubeTranscript") if message.match?(%r{https?://(?:www\.)?youtube\.com/|https?://youtu\.be/})
        return evidence_tool("YoutubeTranscript") if message.match?(/\byoutube transcript\b/i) && message.match?(/\b[A-Za-z0-9_-]{11}\b/)
        return evidence_tool("ArxivResearch") if message.match?(/\b(?:arxiv|ar5iv|academic papers?|research papers?|literature review)\b/i)
        if message.match?(/\b(?:github repos?|github repositories|open[- ]source projects|repo(?:sitory)? mining|popular repositories|trending repositories|best (?:ruby )?(?:gems|libraries|frameworks)|find (?:a few )?(?:projects|repositories|libraries) on github)\b/i)
          return evidence_tool("GitHubRepoMiner")
        end
        nil
      end

      def specialized_web_args(message)
        case
        when message.match?(%r{https://codepen\.io/})
          { mode: "inspect", url: message[%r{https://codepen\.io/[^\s)]+}], limit: 8 }
        when message.match?(%r{https://gist\.github\.com/})
          { url: message[%r{https://gist\.github\.com/[^\s)]+}], full: false }
        when message.match?(%r{https?://(?:www\.)?youtube\.com/|https?://youtu\.be/})
          url = message[%r{https?://(?:www\.)?youtube\.com/[^\s)]+|https?://youtu\.be/[^\s)]+}]
          { url:, timestamps: message.match?(/\b(?:timestamps?|timed notes)\b/i) }
        when message.match?(/\byoutube transcript\b/i) && (video_id = message[/\b[A-Za-z0-9_-]{11}\b/])
          { url: video_id, timestamps: message.match?(/\b(?:timestamps?|timed notes)\b/i) }
        when message.match?(/\b(?:arxiv|ar5iv|academic papers?|research papers?|literature review)\b/i)
          { query: message, sort_by: "relevance", limit: 5 }
        when message.match?(/\b(?:github repos?|github repositories|open[- ]source projects|repo(?:sitory)? mining|popular repositories|trending repositories|best (?:ruby )?(?:gems|libraries|frameworks)|find (?:a few )?(?:projects|repositories|libraries) on github)\b/i)
          { query: message, sort: message.match?(/\b(?:recent|latest|updated|active)\b/i) ? "updated" : "stars", limit: 5 }
        else
          { mode: "trending", limit: 8 }
        end
      end

      def capability_preflight(plugin, action)
        tool = evidence_tool("PluginObserve")
        return unless tool

        result = tool.call(plugin:, action:, args: {})
        return unless result.respond_to?(:ok?) && result.ok?

        value = result.value!.to_s
        "Capability observation (#{plugin}/#{action}):\n#{value[0, 6_000]}"
      rescue StandardError => e
        "Capability observation unavailable: #{e.message}"
      end

      def evidence_tool(name)
        @tools.find { |tool| tool.class.name.to_s.split("::").last == name }
      end

      def check_rate_limit(model_id = nil)
        @circuit_breaker.check_rate!(model_id) if @circuit_breaker.respond_to?(:check_rate!)
        nil
      rescue Io::CircuitBreaker::CircuitError => err
        Result.err(err.message, category: err.category)
      end

      def record_trajectory!(message:, model:, outcome:)
        return unless ENV["MASTER_LLM_RECORD"] == "1"

        events = Array(Fiber[:master_trajectory_events]).dup
        events << { "event" => "outcome", "outcome" => outcome, "model" => model.to_s }
        verified = Master::AI::Trajectory::Benchmark.score(
          "task" => message.to_s,
          "model" => model.to_s,
          "events" => events,
          "outcome" => outcome,
          "verified" => outcome == "complete",
        )["verified"]

        Master::AI::Trajectory::Record.new(
          "task" => message.to_s,
          "model" => model.to_s,
          "events" => events,
          "outcome" => outcome,
          "verified" => verified,
        ).append!(File.join(Master::ROOT, ".master", "trajectories", "trajectories.ndjson"))
      rescue StandardError => e
        @bus&.publish("llm:record_error", error: e.message)
      ensure
        Fiber[:master_trajectory_events] = nil
      end

      def publish_ctx_footer(model_id)
        est = @session.respond_to?(:token_est) ? @session.token_est : 0
        limit = Master.context_window(model_id)
        pct = limit.positive? ? ((est.to_f / limit) * 100).round(1) : 0
        @bus&.publish("ctx:footer", model: model_id, token_est: est, limit:, pct:)
      end

      def prepare_chat_dispatch(message, task_type)
        candidate_models = routed_models(message, task_type:)
        selected_model = candidate_models.first
        @bus&.publish("llm:routed", model: selected_model, task_type: task_type || @config.task_type, reason: "routing")
        prompt = topic_anchored(message)
        context = conversation_context
        tokens_approx = Trace::Session.estimate_tokens(message)
        @bus&.publish("llm:request", model: selected_model, tokens: tokens_approx)
        if ENV["MASTER_LLM_RECORD"] == "1"
          Fiber[:master_trajectory_events] << { "event" => "llm:request", "model" => selected_model, "tokens" => tokens_approx }
        end
        @deps.homeostat&.observe(:llm_call)
        { candidate_models:, selected_model:, prompt:, context: }
      end

      def handle_phantom_recovery(text, message:, image:, stream:, escalation_depth:, task_type:, &blk)
        recovery = Master::PhantomRecovery.handle(text, bus: @bus, session: @session)
        case recovery[:action]
        when :discard
          Result.err("phantom recovery: discarded repetitive response", category: :policy)
        when :escalate
          chat(message, image:, stream:, escalation_depth: escalation_depth + 1, task_type:, &blk) if escalation_depth < 2
        when :halt
          Result.err("phantom recovery: halted after repeated phantom patterns", category: :policy)
        end
      end

      def with_task_type(type)
        return yield unless type && !type.empty?
        old = @config["task_type"]
        @config["task_type"] = type
        yield
      ensure
        @config["task_type"] = old
      end
    end
  end
end
