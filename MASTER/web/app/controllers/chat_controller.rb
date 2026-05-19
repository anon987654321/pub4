# frozen_string_literal: true

require "open3"

class ChatController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:message, :tts, :speak, :enhance]

  def index
    @model = container[:agent].model.to_s.split("/").last
    @tier  = request.env["master.tier"].to_s
    render layout: false
  end

  def dmesg
    out, = Open3.capture2e("dmesg")
    lines = out.lines.first(20).map(&:chomp)
    render json: { lines: lines }
  end

  def metrics
    c = container
    repo_root = Rails.root.join("..").to_s
    out, = Open3.capture2e("git", "-C", repo_root, "status", "--porcelain")
    dirty = out.lines.count
    open_models = c[:breaker].respond_to?(:open_models) ? c[:breaker].open_models : []
    render json: {
      model:            c[:agent].model.to_s.split("/").last,
      tokens:           c[:session].respond_to?(:token_est) ? c[:session].token_est : 0,
      cost:             "$%.4f" % (c[:session].respond_to?(:cost) ? c[:session].cost : 0.0),
      uptime:           ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - start_ms),
      repo_dirty_count: dirty,
      open_breakers:    open_models,
      tier:             request.env["master.tier"].to_s
    }
  end

  def history
    messages = container[:session].messages.last(200).map { |m| { role: m[:role], content: m[:content].to_s[0, 2000] } }
    render json: messages
  end

  def command
    cmd = params[:command] || JSON.parse(request.body.read)["command"]
    result = container[:gateway].receive(channel: :cli, message: cmd)
    output = result.ok? ? (result.value[:rendered] || result.value.to_s) : result.message
    render json: { output: output }
  rescue StandardError => e
    render json: { output: "Error: #{e.message}" }, status: 500
  end

  def enhance
    msg = params[:message].to_s.strip
    return render(json: { changed: false }) if msg.empty?

    result = Master::Now::Stages::Enhance.run(msg, agent: container[:agent], event_bus: container[:bus])
    render json: result
  rescue StandardError => e
    render json: { changed: false, error: e.message }
  end

  def message
    input = params[:message].to_s.strip
    return head(:bad_request) if input.empty?

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    visitor = request.env["master.tier"] != "authenticated"
    Fiber[:master_visitor] = visitor

    sse = response.stream
    begin
      streamed  = false
      tool_sub  = container[:bus].subscribe("tool:before") do |ev|
        begin
          payload = { tool: ev[:tool].to_s, path: ev[:path].to_s }.to_json
          sse.write("event: tool\ndata: #{payload}\n\n")
        rescue StandardError => _e
          nil
        end
      end
      # Bridge bus state → named SSE events so the face UI can react gesturally.
      mood_sub      = container[:bus].subscribe("agent:mood")        { |ev| sse.write("event: mood\ndata: #{ev[:mood] || ev[:value]}\n\n") rescue nil }
      model_sub     = container[:bus].subscribe("llm:request")       { |ev| sse.write("event: model\ndata: #{ev[:model]}\n\n") rescue nil }
      # dmesg stream — all bus activity as OpenBSD dmesg(8)-style dim lines.
      dmesg_sub = container[:bus].subscribe("*") do |ev|
        line = dmesg_format(ev[:event].to_s, ev)
        sse.write("event: dmesg\ndata: #{line.to_json}\n\n") rescue nil
      end
      verdict_sub   = container[:bus].subscribe("tribunal:rendered") do |ev|
        v = ev[:vetoes].to_i.positive? ? "veto" : (ev[:judge] ? "pass" : "unclear")
        sse.write("event: verdict\ndata: #{v}\n\n") rescue nil
      end
      escalate_sub  = container[:bus].subscribe("llm:escalation")    { |_| sse.write("event: confidence\ndata: 0.4\n\n") rescue nil }
      enhance_sub   = container[:bus].subscribe("enhance:rewrite") do |ev|
        sse.write("event: enhance\ndata: #{ev[:enhanced].to_s.gsub("\n", "\\n").to_json}\n\n") rescue nil
      end
      # Publish incoming canvas state into bus so prompt-builder can include it.
      if (st = params[:state]).present?
        mood, mode, idle_s, palette = st.to_s.split("|")
        container[:bus].publish(:canvas_state, mood:, mode:, idle_s: idle_s.to_i, palette: palette.to_i) rescue nil
      end

      on_chunk = ->(token) {
        streamed = true
        encoded = token.to_s.gsub("\\", "\\\\").gsub("\n", "\\n")
        sse.write("data: #{encoded}\n\n")
      }

      ctx = { user_message: input, on_chunk: on_chunk, visitor: visitor }
      ctx[:pre_enhanced] = true if params[:pre_enhanced].present?
      ctx[:voice] = true if params[:voice].present?
      if (img = params[:image]).present?
        ctx[:image] = { data: img[:data].to_s, mime: img[:mime].to_s, name: img[:name].to_s }
      end

      # P2: ack backchannel for long messages — bridges silence while LLM thinks.
      container[:bus].publish("speak:backchannel", reason: "user_long_input") if input.length >= 120

      mutated_flag    = false
      mutated_paths   = []
      mutate_sub = container[:bus].subscribe("tool:after") do |ev|
        next unless %w[Write Edit Create FilePatch].include?(ev[:tool].to_s)
        mutated_flag = true
        path = ev[:path].to_s
        mutated_paths << path unless path.empty?
      end

      result = container[:pipeline].call(Master::Result.ok(**ctx))

      unless streamed
        text = case result
               when Master::Result::Ok
                 val = result.value
                 val.is_a?(Hash) && val[:rendered] ? val[:rendered] : val.to_s
               when Master::Result::Err
                 "ERROR: #{result.message}"
               end
        unless text.to_s.strip.empty?
          encoded = text.to_s.gsub("\\", "\\\\").gsub("\n", "\\n")
          sse.write("data: #{encoded}\n\n")
        end
      end

      sse.write("data: [DONE]\n\n")

      if mutated_flag
        container[:bus].publish("auto:auto_start", reason: "post_chat_mutation")
        if mutated_paths.any?
          Thread.new do
            Thread.current.report_on_exception = false
            repo_root = Rails.root.join("..", "..").to_s
            msg = "auto: chat-turn mutation (#{mutated_paths.size} file(s))"
            paths_to_add = mutated_paths.select { |p| File.exist?(p) }
            next if paths_to_add.empty?
            _, status = Open3.capture2e("git", "-C", repo_root, "add", "--", *paths_to_add)
            if status.success?
              _, st = Open3.capture2e("git", "-C", repo_root, "commit", "-m", msg)
              container[:bus].publish("autocommit:done", ok: st.success?)
            end
          rescue StandardError => err
            container[:bus].publish("autocommit:error", error: err.message)
          end
        end
      end
    rescue StandardError => e
      sse.write("data: ERROR: #{e.message}\n\n")
      sse.write("data: [DONE]\n\n")
    ensure
      Fiber[:master_visitor] = nil
      begin
        tool_sub.call if defined?(tool_sub) && tool_sub
        mutate_sub.call if defined?(mutate_sub) && mutate_sub
        mood_sub.call if defined?(mood_sub) && mood_sub
        model_sub.call if defined?(model_sub) && model_sub
        verdict_sub.call if defined?(verdict_sub) && verdict_sub
        escalate_sub.call if defined?(escalate_sub) && escalate_sub
        enhance_sub.call  if defined?(enhance_sub)  && enhance_sub
        dmesg_sub.call    if defined?(dmesg_sub)    && dmesg_sub
      rescue StandardError => _e
        nil
      end
      sse.close
    end
  end

  def speak
    text = params[:text].to_s.strip
    return head(:bad_request) if text.empty?
    container[:bus].publish("speak:text", { text: text })
    head :ok
  end

  def tts
    text = params[:text].to_s.strip
    return head(:bad_request) if text.empty?

    voice = params[:voice].to_s.downcase.to_sym
    style = params[:style].to_s.downcase.to_sym
    voice = Master::Voice::Speech::DEFAULT_VOICE unless Master::Voice::Speech::VOICES.key?(voice)
    # :auto opts in to per-clause infer_style. Otherwise enforce whitelist.
    style = Master::Voice::Speech::DEFAULT_STYLE if style != :auto && !Master::Voice::Speech::STYLES.key?(style)

    audio = Master::Voice::Speech.synthesize_audio(text, voice: voice, style: style)
    if audio&.bytes && audio.bytes.bytesize.positive?
      send_data audio.bytes, type: audio.mime_type, disposition: "inline"
    else
      head :service_unavailable
    end
  rescue StandardError => e
    logger.error "TTS failed: #{e.message}"
    head :service_unavailable
  end

  private

  # Format any bus event as an OpenBSD dmesg(8)-style line.
  # Pattern: <subsystem><unit> at <bus>: <description>
  def dmesg_format(event, payload)
    sub, rest = event.split(":", 2)
    desc = case event
           when "tool:before"
             tool = payload[:tool].to_s.downcase.split("::").last
             path = payload[:path].to_s
             path.empty? ? tool : "#{tool} #{path}"
           when "llm:request"
             model = payload[:model].to_s.split("/").last
             tokens = payload[:tokens]
             tokens ? "→ #{model} (#{tokens} tokens)" : "→ #{model}"
           when "llm:escalation"    then "escalation depth #{payload[:depth]}"
           when "enhance:rewrite"
             o = payload[:original].to_s.length
             e = payload[:enhanced].to_s.length
             "rewrite #{o}→#{e} chars"
           when "pipeline:rollback" then "rollback #{payload[:category]} #{payload[:tag].to_s.split(":").last}"
           when "pipeline:stage"    then "stage #{payload[:stage]} #{payload[:ms]}ms"
           when "fix_loop:pass_start" then "pass #{payload[:pass]}"
           when "fix_loop:clean"      then "clean #{payload[:consecutive_clean]}/2"
           when "fix_loop:plateau"    then "plateau #{payload[:violations]} violations"
           when "fix_loop:ast_fixed"  then "ast #{payload[:transforms]&.join(",")}"
           when "tribunal:rendered"
             v = payload[:vetoes].to_i.positive? ? "veto" : "pass"
             "#{v} #{payload[:judge]}"
           when "backup:ok"         then "synced #{payload[:bytes]}B"
           when "backup:error"      then "error #{payload[:error]}"
           when "scan:complete"     then "#{payload[:count]} violations"
           when "autoloop:cycle"    then "autoloop #{payload[:pass]}/#{payload[:max]}"
           when "pressure:updated"  then return nil  # too noisy — skip
           when /\Apipeline:/       then return nil  # internal, skip
           when /\Acanvas_/         then return nil
           else
             rest&.tr("_", " ") || sub
           end
    return nil if desc.nil?
    "#{sub}0 at master0: #{desc}"
  end
end