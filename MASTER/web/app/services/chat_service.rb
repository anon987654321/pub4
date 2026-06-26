# frozen_string_literal: true

require "json"
require "open3"

class ChatService
  SMOKE_MESSAGES = %w[ping pong health up].freeze

  COUNCIL_PERSONA_VOICE = {
    "Architect" => :osman,
    "Skeptic" => :wayne,
    "Pragmatist" => :osman,
    "Security" => :wayne,
    "User" => :osman,
    "Mentor" => :ezinne
  }.freeze

  WRITE_TOOLS = %w[Write Edit Create FilePatch].freeze
  BUS_DMESG_SKIP = %w[
    infer:resolved infer:confidence tool:before tool:after client_action
    pipeline:stage_start pipeline:stage_complete felt:sense pressure:updated
  ].freeze
  BUS_THOUGHT_RE = /:(?:done|error|warn|crit|resolved|confidence|detected)\b/.freeze

  def initialize(container:, params:, stream:, logger:, tier:, unlocked:, author:)
    @container = container
    @params = params
    @stream = stream
    @logger = logger
    @tier = tier
    @unlocked = unlocked
    @author = author
    @subscriptions = []
    @mutated_paths = []
    @mutated = false
  end

  def call
    stream_open!
    if smoke_reply?
      write_chunk(smoke_response)
      @stream.write("data: [DONE]\n\n")
      return
    end

    prepare_turn
    subscribe_to_events
    publish_canvas_state
    result = @container[:pipeline].call(Master::Result.ok(**pipeline_context))
    write_fallback(result)
    write_turn_ctx_footer
    @stream.write("data: [DONE]\n\n")
    trigger_post_mutation_work
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "ChatService.call", event_bus: @container&.dig(:bus))
    @stream.write("data: #{escape_sse(Master::Ground::Redactor.public_error_message)}\n\n")
    @stream.write("data: [DONE]\n\n")
  ensure
    clear_fiber_flags
    unsubscribe_all
    @stream.close
  end

  private

  def stream_open!
    @stream.write(": connected\n\n")
  end

  def smoke_reply?
    SMOKE_MESSAGES.include?(@params[:message].to_s.strip.downcase)
  end

  def smoke_response
    case @params[:message].to_s.strip.downcase
    when "ping" then "pong"
    when "pong" then "ping"
    when "health", "up" then "ok"
    else "ok"
    end
  end

  def prepare_turn
    input = @params[:message].to_s.strip
    @container[:bus].publish("user:interrupt", reason: "new_turn", source: "chat")
    @container[:bus]&.publish("input:long", length: input.length) if input.length > 180
    Fiber[:master_visitor] = @tier != "authenticated"
    Fiber[:master_elevated] = @unlocked || @author
  end

  def subscribe_to_events
    subscribe("tool:before") { |ev| write_json_event("tool", tool_payload(ev)) }
    subscribe("react:tool_calls") { |ev| write_json_event("tool_stack", stack_payload(ev)) }
    subscribe("agent:mood") { |ev| write_event("mood", ev[:mood] || ev[:value]) }
    subscribe("llm:request") { |ev| write_event("model", ev[:model]) }
    subscribe("ctx:footer") { |ev| write_json_event("ctx_footer", ctx_footer_payload(ev)) }
    subscribe("compaction:done") { |ev| write_compaction_event(ev) }
    subscribe("phantom:detected") { |ev| write_json_event("phantom", phantom_payload(ev)) }
    subscribe("pipeline:stage_start") { |ev| write_json_event("stage", { stage: ev[:stage], phase: "start" }) }
    subscribe("pipeline:stage_complete") { |ev| write_json_event("stage", { stage: ev[:stage], phase: "done", ms: ev[:ms] }) }
    subscribe("btw:done") { |ev| write_json_event("btw", { type: ev[:type], summary: ev[:summary].to_s[0, 500] }) }
    subscribe("skills:triggered") { |ev| write_json_event("thought", "skill #{ev[:skill]}") }
    subscribe("felt:sense") { |ev| write_json_event("felt", { mood: ev[:mood], entropy: ev[:entropy], confidence: ev[:confidence] }) }
    subscribe("infer:resolved") { |ev| write_json_event("dmesg", dmesg_format("infer:resolved", ev)) }
    subscribe("infer:confidence") { |ev| write_json_event("dmesg", dmesg_format("infer:confidence", ev)) }
    subscribe("pressure:updated") { |ev| write_json_event("pressure", ev.slice(:value, :tokens, :limit, :pct)) }
    subscribe("**") do |ev|
      name = ev[:event].to_s
      next if BUS_DMESG_SKIP.include?(name)
      write_json_event("dmesg", dmesg_format(name, ev))
    end
    subscribe("**") do |ev|
      name = ev[:event].to_s
      next if BUS_DMESG_SKIP.include?(name)
      next unless name.match?(BUS_THOUGHT_RE)
      write_json_event("thought", thought_format(name, ev))
    end
    subscribe("tribunal:rendered") { |ev| write_event("verdict", verdict_for(ev)) }
    subscribe("llm:escalation") { |_ev| write_event("confidence", "0.4") }
    subscribe("enhance:rewrite") { |ev| write_json_event("enhance", ev[:enhanced].to_s.gsub("\n", "\\n")) }
    subscribe(:council_feedback) { |ev| write_council_speech(ev) }
    subscribe("tool:after") { |ev| track_mutation(ev) }
    subscribe("client_action") { |ev| write_json_event("client_action", client_action_payload(ev)) }
  end

  def pipeline_context
    {
      user_message: @params[:message].to_s.strip,
      on_chunk: method(:write_chunk),
      felt_sense: felt_sense_payload
    }.tap do |ctx|
      ctx[:pre_enhanced] = true if @params[:pre_enhanced].present?
      ctx[:voice] = true if @params[:voice].present?
      ctx[:image] = image_payload if image_payload
    end
  end

  def image_payload
    @image_payload ||= begin
      img = @params[:image]
      if img.present?
        { data: img[:data].to_s, mime: img[:mime].to_s, name: img[:name].to_s }
      elsif @params[:image_token].present?
        ImagePresenter.new(logger: @logger).payload(@params[:image_token])
      end
    end
  end

  def publish_canvas_state
    return unless @params[:state].present?

    parts = @params[:state].to_s.split("|")
    mood, mode = parts.values_at(0, 1)
    entropy = parts[2].to_f
    confidence = parts[3].to_f
    arousal = parts[4].to_f
    valence = parts[5].to_f
    hist_entropy = parts[6].to_f
    felt = { mood:, mode:, entropy:, confidence:, arousal:, valence:, hist_entropy: }
    @container[:bus].publish(:canvas_state, **felt)
    @container[:bus].publish("felt:sense", **felt)
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "ChatService.publish_canvas_state", event_bus: @container[:bus])
  end

  def write_fallback(result)
    return if @streamed

    text = rendered_text(result)
    return if text.to_s.strip.empty?

    write_chunk(text)
  end

  def rendered_text(result)
    case result
    when Master::Result::Ok
      val = result.value
      rendered = val.respond_to?(:[]) ? val[:rendered].to_s : ""
      rendered.empty? ? val.to_s : rendered
    when Master::Result::Err
      if result.category == :no_api_key
        result.message
      else
        Master::Ground::Redactor.public_error_message
      end
    end
  end

  def write_chunk(token)
    text = token.to_s
    return if text.empty?

    @streamed = true
    @stream.write("data: #{escape_sse(text)}\n\n")
  end

  def write_event(event, data)
    @stream.write("event: #{event}\ndata: #{data}\n\n")
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "ChatService.write_event", event_bus: @container[:bus])
  end

  def write_json_event(event, data)
    return if data.nil?

    @stream.write("event: #{event}\ndata: #{data.to_json}\n\n")
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "ChatService.write_json_event", event_bus: @container[:bus])
  end

  def write_council_speech(event)
    persona = event[:persona].to_s
    face = Master::Voice::CouncilFace.for_persona(persona)
    voice = face[:voice] || COUNCIL_PERSONA_VOICE[persona] || Master::Voice::Speech::DEFAULT_VOICE
    sentence = event[:feedback].to_s.strip.split(/(?<=[.!?])\s+/).first(2).join(" ").strip[0, 200]
    return if sentence.empty?

    viseme_plan = Master::Voice::Expression.viseme_hints(sentence).each_with_index.map do |hint, i|
      { shape: hint[:shape], amp: hint[:amp], t: hint[:ms] * i }
    end
    expression = face[:expression] || Master::Voice::Expression.for_council_persona(persona)
    write_json_event("council:speech", {
      voice: voice.to_s,
      text: sentence,
      persona: persona,
      label: face[:label],
      position: face[:position].to_s,
      viseme_lane: face[:viseme_lane].to_s,
      blendshapes: face[:blendshapes],
      expression: expression,
      viseme_plan: viseme_plan
    })
  end

  def subscribe(event, &block)
    @subscriptions << @container[:bus].subscribe(event, &block)
  end

  def unsubscribe_all
    @subscriptions.each do |unsubscribe|
      unsubscribe.call
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "ChatService.unsubscribe_one", event_bus: @container[:bus])
    end
  end

  def clear_fiber_flags
    Fiber[:master_visitor] = nil
    Fiber[:master_elevated] = nil
  end

  def tool_payload(event)
    path = event[:path].to_s
    {
      tool: event[:tool].to_s,
      path: path.empty? ? "" : File.basename(path),
      command: Master::Ground::Redactor.text(event[:command].to_s)
    }
  end

  def stack_payload(event)
    {
      count: event[:count], step: event[:step], model: event[:model].to_s,
      tool: event[:tool].to_s, path: event[:path].to_s,
      diff: event[:diff].to_s[0, 4000]
    }
  end

  def ctx_footer_payload(event)
    {
      model: event[:model].to_s.split("/").last,
      token_est: event[:token_est],
      limit: event[:limit],
      pct: event[:pct]
    }
  end

  def phantom_payload(event)
    { patterns: Array(event[:patterns]), recovery: Array(event[:recovery]) }
  end

  def client_action_payload(event)
    event.slice(:action, :url, :label).compact
  end

  def felt_sense_payload
    return nil unless @params[:state].present?

    parts = @params[:state].to_s.split("|")
    {
      mood: parts[0],
      mode: parts[1],
      entropy: parts[2].to_f,
      confidence: parts[3].to_f,
      arousal: parts[4].to_f,
      valence: parts[5].to_f,
      hist_entropy: parts[6].to_f
    }
  rescue StandardError
    nil
  end

  def write_turn_ctx_footer
    session = @container[:session]
    return unless session.respond_to?(:token_est)

    est = session.token_est
    limit = Master::CTX_WINDOW_SIZE
    pct = limit.positive? ? ((est.to_f / limit) * 100).round(1) : 0
    model = @container[:agent].model.to_s.split("/").last
    write_json_event("ctx_footer", { model:, token_est: est, limit:, pct: })
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "ChatService.write_turn_ctx_footer", event_bus: @container[:bus])
  end

  def write_compaction_event(event)
    summary = event[:summary].to_s.strip
    write_json_event("compaction", { summary: summary[0, 2_000], token_est: event[:token_est] })
    bullets = summary.lines.map(&:strip).reject(&:empty?).first(8).join("; ")
    write_json_event("dmesg", "compact0 at master0: context compacted — #{bullets}")
  end

  def verdict_for(event)
    event[:vetoes].to_i.positive? ? "veto" : (event[:judge] ? "pass" : "unclear")
  end

  def track_mutation(event)
    return unless WRITE_TOOLS.include?(event[:tool].to_s)

    @mutated = true
    path = event[:path].to_s
    @mutated_paths << path unless path.empty?
  end

  def trigger_post_mutation_work
    return unless @mutated

    @container[:bus].publish("auto:auto_start", reason: "post_chat_mutation")
    publish_mutation_review if @mutated_paths.any?
  end

  def publish_mutation_review
    paths = @mutated_paths.select { |path| File.exist?(path) }
    return if paths.empty?

    @container[:bus].publish(
      "chat:mutation_pending_review",
      count: paths.size,
      paths: paths.map { |path| File.basename(path) }
    )
  end

  def escape_sse(text)
    text.gsub("\\", "\\\\").gsub("\n", "\\n")
  end

  def thought_format(event, payload)
    case event
    when "enhance:rewrite" then "refining your prompt for clarity"
    when "llm:request" then thought_model(payload)
    when "llm:escalation" then "escalating to a deeper model (depth #{payload[:depth]})"
    when "tool:before" then thought_tool(payload)
    when "council_feedback", :council_feedback then thought_council(payload)
    when "tribunal:rendered" then "tribunal #{payload[:vetoes].to_i.positive? ? "vetoed" : "approved"}"
    when "pipeline:stage" then thought_stage(payload)
    when "pipeline:stage_start" then thought_stage(payload.merge(stage: payload[:stage]))
    when "pipeline:stage_complete" then "#{payload[:stage]} #{payload[:ms]}ms"
    when "phantom:detected" then "phantom guard: #{Array(payload[:patterns]).join(', ')}"
    when "compaction:done" then "compacted context (#{payload[:token_est]} tokens remain)"
    end
  end

  def thought_model(payload)
    model = payload[:model].to_s.split("/").last
    model.empty? ? "thinking" : "thinking with #{model}"
  end

  def thought_tool(payload)
    tool = payload[:tool].to_s.split("::").last.to_s.downcase
    path = payload[:path].to_s
    path.empty? ? "using #{tool}" : "using #{tool} on #{File.basename(path)}"
  end

  def thought_council(payload)
    persona = payload[:persona].to_s
    persona.empty? ? "council deliberating" : "#{persona} weighs in"
  end

  def thought_stage(payload)
    stage = payload[:stage].to_s
    stages = %w[enhance infer route guard execute council deliberate prune memo render]
    stages.include?(stage) ? "entering #{stage}" : nil
  end

  def dmesg_format(event, payload)
    sub, rest = event.split(":", 2)
    desc = dmesg_description(event, payload, sub, rest)
    return nil if desc.nil?

    "#{sub}0 at master0: #{desc}"
  end

  def dmesg_description(event, payload, sub, rest)
    case event
    when "tool:before" then dmesg_tool(payload)
    when "llm:request" then dmesg_model(payload)
    when "llm:escalation" then "escalation depth #{payload[:depth]}"
    when "enhance:rewrite" then "rewrite #{payload[:original].to_s.length}->#{payload[:enhanced].to_s.length} chars"
    when "pipeline:rollback" then "rollback #{payload[:category]} #{payload[:tag].to_s.split(":").last}"
    when "pipeline:stage" then "stage #{payload[:stage]} #{payload[:ms]}ms"
    when "fix_loop:pass_start" then "pass #{payload[:pass]}"
    when "fix_loop:clean" then "clean #{payload[:consecutive_clean]}/2"
    when "fix_loop:plateau" then "plateau #{payload[:violations]} violations"
    when "fix_loop:ast_fixed" then "ast #{payload[:transforms]&.join(",")}"
    when "tribunal:rendered" then "#{payload[:vetoes].to_i.positive? ? "veto" : "pass"} #{payload[:judge]}"
    when "backup:ok" then "synced #{payload[:bytes]}B"
    when "backup:error" then "error #{payload[:error]}"
    when "scan:complete" then "#{payload[:count]} violations"
    when "autoloop:cycle" then "autoloop #{payload[:pass]}/#{payload[:max]}"
    when "pressure:updated" then "pressure #{payload[:value]}"
    when "cache:hit" then "cache hit #{payload[:key]}"
    when "cache:miss" then "cache miss #{payload[:key]}"
    when "compaction:done" then "compacted ctx to #{payload[:token_est]} tokens"
    when "compaction:start" then "compaction at #{payload[:token_est]} tokens"
    when "phantom:detected" then "phantom #{Array(payload[:patterns]).join(',')}"
    when "btw:done" then "btw #{payload[:type]} done"
    when "agent:start" then "agent #{payload[:type]} start"
    when "agent:end" then "agent #{payload[:type]} end"
    else rest&.tr("_", " ") || sub
    end
  end

  def dmesg_tool(payload)
    tool = payload[:tool].to_s.downcase.split("::").last
    path = payload[:path].to_s
    path.empty? ? tool : "#{tool} #{File.basename(path)}"
  end

  def dmesg_model(payload)
    model = payload[:model].to_s.split("/").last
    tokens = payload[:tokens]
    tokens ? "-> #{model} (#{tokens} tokens)" : "-> #{model}"
  end
end
