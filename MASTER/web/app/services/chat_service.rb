# frozen_string_literal: true

require "json"
require "open3"

class ChatService
  COUNCIL_PERSONA_VOICE = ChatController::COUNCIL_PERSONA_VOICE

  def initialize(container:, sse:, message_params:, visitor: false)
    @container = container
    @sse = sse
    @mp = message_params
    @visitor = visitor
    @streamed = false
    @subs = []
  end

  def stream_turn!
    input = @mp[:message].to_s.strip
    @container[:bus].publish("user:interrupt", reason: "new_turn", source: "chat")
    @container[:bus]&.publish("input:long", length: input.length) if input.length > 180

    subscribe_bus_events
    on_chunk = build_chunk_handler
    ctx = build_context(input, on_chunk)
    mutation_state = track_mutations
    result = @container[:pipeline].call(Master::Result.ok(**ctx))
    emit_fallback(result) unless @streamed
    @sse.write("data: [DONE]\n\n")
    autocommit_if_needed(mutation_state)
  ensure
    @subs.each(&:call)
  end

  private

  def subscribe_bus_events
    bus = @container[:bus]
    @subs << bus.subscribe("tool:before") { |ev| write_event("tool", { tool: ev[:tool].to_s, path: ev[:path].to_s }) }
    @subs << bus.subscribe("agent:mood") { |ev| @sse.write("event: mood\ndata: #{ev[:mood] || ev[:value]}\n\n") rescue nil }
    @subs << bus.subscribe("llm:request") { |ev| @sse.write("event: model\ndata: #{ev[:model]}\n\n") rescue nil }
    @subs << bus.subscribe("pipeline:stage_start") { |ev| @sse.write("event: pipeline\ndata: #{ev[:stage]}\n\n") rescue nil }
    @subs << bus.subscribe("**") { |ev| line = ChatSseFormatter.dmesg_format(ev[:event].to_s, ev); write_event("dmesg", line) if line }
    @subs << bus.subscribe("**") { |ev| line = ChatSseFormatter.thought_format(ev[:event].to_s, ev); write_event("thought", line) if line }
    @subs << bus.subscribe("tribunal:rendered") { |ev| v = ev[:vetoes].to_i.positive? ? "veto" : (ev[:judge] ? "pass" : "unclear"); @sse.write("event: verdict\ndata: #{v}\n\n") rescue nil }
    @subs << bus.subscribe("llm:escalation") { |_| @sse.write("event: confidence\ndata: 0.4\n\n") rescue nil }
    @subs << bus.subscribe("enhance:rewrite") { |ev| @sse.write("event: enhance\ndata: #{ev[:enhanced].to_s.gsub("\n", "\\n").to_json}\n\n") rescue nil }
    @subs << bus.subscribe(:council_feedback) { |ev| emit_council_speech(ev) }
  end

  def build_chunk_handler
    lambda do |token|
      t = token.to_s
      return if t.empty?
      @streamed = true
      cleaned = Master::Voice::SoulDriftDetector.clean(t, event_bus: @container[:bus])
      @sse.write("data: #{cleaned.gsub("\\", "\\\\").gsub("\n", "\\n")}\n\n")
    end
  end

  def build_context(input, on_chunk)
    ctx = { user_message: input, on_chunk: on_chunk }
    ctx[:pre_enhanced] = true if @mp[:pre_enhanced].present?
    ctx[:voice] = true if @mp[:voice].present?
    attach_image!(ctx)
    publish_canvas_state!
    ctx
  end

  def attach_image!(ctx)
    if (img = @mp[:image]).present?
      ctx[:image] = { data: img[:data].to_s, mime: img[:mime].to_s, name: img[:name].to_s }
    elsif (token = @mp[:image_token]).present?
      payload = ImagePresenter.payload_for(token)
      ctx[:image] = payload if payload
    end
  end

  def publish_canvas_state!
    return unless (st = @mp[:state]).present?
    mood, mode, idle_s, palette = st.to_s.split("|")
    @container[:bus].publish(:canvas_state, mood:, mode:, idle_s: idle_s.to_i, palette: palette.to_i) rescue nil
  end

  def track_mutations
    state = { flag: false, paths: [] }
    @subs << @container[:bus].subscribe("tool:after") do |ev|
      next unless %w[Write Edit Create FilePatch].include?(ev[:tool].to_s)
      state[:flag] = true
      path = ev[:path].to_s
      state[:paths] << path unless path.empty?
    end
    state
  end

  def emit_fallback(result)
    text = case result
           when Master::Result::Ok
             val = result.value
             rendered = val.respond_to?(:[]) ? val[:rendered].to_s : ""
             rendered.empty? ? val.to_s : rendered
           when Master::Result::Err
             result.category == :no_api_key ? result.message : "ERROR: #{result.message}"
           end
    text = Master::Voice::SoulDriftDetector.clean(text, event_bus: @container[:bus])
    return if text.to_s.strip.empty?
    encoded = text.to_s.gsub("\\", "\\\\").gsub("\n", "\\n")
    @sse.write("data: #{encoded}\n\n")
  end

  def autocommit_if_needed(state)
    return unless state[:flag]
    @container[:bus].publish("auto:auto_start", reason: "post_chat_mutation")
    paths = state[:paths].select { |p| File.exist?(p) }
    return if paths.empty?
    Thread.new do
      Thread.current.report_on_exception = false
      repo_root = Rails.root.join("..", "..").to_s
      msg = "auto: chat-turn mutation (#{paths.size} file(s))"
      _, status = Open3.capture2e("git", "-C", repo_root, "add", "--", *paths)
      if status.success?
        _, st = Open3.capture2e("git", "-C", repo_root, "commit", "-m", msg)
        @container[:bus].publish("autocommit:done", ok: st.success?)
      end
    rescue StandardError => err
      @container[:bus].publish("autocommit:error", error: err.message)
    end
  end

  def emit_council_speech(ev)
    persona = ev[:persona].to_s
    voice = COUNCIL_PERSONA_VOICE[persona] || Master::Voice::Speech::DEFAULT_VOICE
    raw = ev[:feedback].to_s.strip
    sentence = raw.split(/(?<=[.!?])\s+/).first(2).join(" ").strip[0, 200]
    return if sentence.empty?
    payload = { voice: voice.to_s, text: sentence, persona: persona }.to_json
    @sse.write("event: council:speech\ndata: #{payload}\n\n") rescue nil
  end

  def write_event(name, payload)
    data = payload.is_a?(String) ? payload.to_json : payload.to_json
    @sse.write("event: #{name}\ndata: #{data}\n\n") rescue nil
  end
end