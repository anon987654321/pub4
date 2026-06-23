# frozen_string_literal: true

require "json"
require "open3"

class ChatService
  COUNCIL_PERSONA_VOICE = {
    "Architect" => :osman,
    "Skeptic" => :wayne,
    "Pragmatist" => :osman,
    "Security" => :wayne,
    "User" => :osman,
    "Mentor" => :ezinne
  }.freeze

  WRITE_TOOLS = %w[Write Edit Create FilePatch].freeze

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
    prepare_turn
    subscribe_to_events
    publish_canvas_state
    result = @container[:pipeline].call(Master::Result.ok(**pipeline_context))
    write_fallback(result)
    @stream.write("data: [DONE]\n\n")
    trigger_post_mutation_work
  rescue StandardError => e
    @stream.write("data: ERROR: #{e.message}\n\n")
    @stream.write("data: [DONE]\n\n")
  ensure
    clear_fiber_flags
    unsubscribe_all
    @stream.close
  end

  private

  def prepare_turn
    input = @params[:message].to_s.strip
    @container[:bus].publish("user:interrupt", reason: "new_turn", source: "chat")
    @container[:bus]&.publish("input:long", length: input.length) if input.length > 180
    Fiber[:master_visitor] = @tier != "authenticated"
    Fiber[:master_elevated] = @unlocked || @author
  end

  def subscribe_to_events
    subscribe("tool:before") { |ev| write_json_event("tool", tool_payload(ev)) }
    subscribe("agent:mood") { |ev| write_event("mood", ev[:mood] || ev[:value]) }
    subscribe("llm:request") { |ev| write_event("model", ev[:model]) }
    subscribe("**") { |ev| write_json_event("dmesg", dmesg_format(ev[:event].to_s, ev)) }
    subscribe("**") { |ev| write_json_event("thought", thought_format(ev[:event].to_s, ev)) }
    subscribe("tribunal:rendered") { |ev| write_event("verdict", verdict_for(ev)) }
    subscribe("llm:escalation") { |_ev| write_event("confidence", "0.4") }
    subscribe("enhance:rewrite") { |ev| write_json_event("enhance", ev[:enhanced].to_s.gsub("\n", "\\n")) }
    subscribe(:council_feedback) { |ev| write_council_speech(ev) }
    subscribe("tool:after") { |ev| track_mutation(ev) }
  end

  def pipeline_context
    {
      user_message: @params[:message].to_s.strip,
      on_chunk: method(:write_chunk)
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

    mood, mode, idle_s, palette = @params[:state].to_s.split("|")
    @container[:bus].publish(:canvas_state, mood: mood, mode: mode, idle_s: idle_s.to_i, palette: palette.to_i)
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
      result.category == :no_api_key ? result.message : "ERROR: #{result.message}"
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
    voice = COUNCIL_PERSONA_VOICE[persona] || Master::Voice::Speech::DEFAULT_VOICE
    sentence = event[:feedback].to_s.strip.split(/(?<=[.!?])\s+/).first(2).join(" ").strip[0, 200]
    return if sentence.empty?

    write_json_event("council:speech", { voice: voice.to_s, text: sentence, persona: persona })
  end

  def subscribe(event, &block)
    @subscriptions << @container[:bus].subscribe(event, &block)
  end

  def unsubscribe_all
    @subscriptions.each(&:call)
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "ChatService.unsubscribe_all", event_bus: @container[:bus])
  end

  def clear_fiber_flags
    Fiber[:master_visitor] = nil
    Fiber[:master_elevated] = nil
  end

  def tool_payload(event)
    { tool: event[:tool].to_s, path: event[:path].to_s }
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
    autocommit_mutations if @mutated_paths.any?
  end

  def autocommit_mutations
    paths = @mutated_paths.select { |path| File.exist?(path) }
    return if paths.empty?

    Thread.new do
      Thread.current.report_on_exception = false
      repo_root = Rails.root.join("..", "..").to_s
      msg = "auto: chat-turn mutation (#{paths.size} file(s))"
      _, status = Open3.capture2e("git", "-C", repo_root, "add", "--", *paths)
      if status.success?
        _, commit_status = Open3.capture2e("git", "-C", repo_root, "commit", "-m", msg)
        @container[:bus].publish("autocommit:done", ok: commit_status.success?)
      end
    rescue StandardError => e
      @container[:bus].publish("autocommit:error", error: e.message)
    end
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
    else rest&.tr("_", " ") || sub
    end
  end

  def dmesg_tool(payload)
    tool = payload[:tool].to_s.downcase.split("::").last
    path = payload[:path].to_s
    path.empty? ? tool : "#{tool} #{path}"
  end

  def dmesg_model(payload)
    model = payload[:model].to_s.split("/").last
    tokens = payload[:tokens]
    tokens ? "-> #{model} (#{tokens} tokens)" : "-> #{model}"
  end
end
