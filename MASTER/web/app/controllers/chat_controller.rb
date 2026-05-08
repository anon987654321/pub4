# frozen_string_literal: true

require "open3"

class ChatController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:message, :tts, :speak]

  def index
    @model = container[:agent].model.to_s.split("/").last
    @tier  = session[:tier].to_s
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
      tier:             session[:tier].to_s
    }
  end

  def message
    input = params[:message].to_s.strip
    return head(:bad_request) if input.empty?

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    visitor = session[:tier] != "authenticated"
    Fiber[:master_visitor] = visitor

    sse = response.stream
    begin
      streamed  = false
      tool_sub  = container[:bus].subscribe("tool:before") do |ev|
        begin
          payload = { tool: ev[:tool].to_s, path: ev[:path].to_s }.to_json
          sse.write("event: tool\ndata: #{payload}\n\n")
        rescue StandardError
          nil
        end
      end

      on_chunk = ->(token) {
        streamed = true
        encoded = token.to_s.gsub("\\", "\\\\").gsub("\n", "\\n")
        sse.write("data: #{encoded}\n\n")
      }

      ctx = { user_message: input, on_chunk: on_chunk, visitor: visitor }
      ctx[:voice] = true if params[:voice].present?
      if (img = params[:image]).present?
        ctx[:image] = { data: img[:data].to_s, mime: img[:mime].to_s, name: img[:name].to_s }
      end

      # P2: ack backchannel for long messages — bridges silence while LLM thinks.
      container[:bus].publish("speak:backchannel", reason: "user_long_input") if input.length >= 120

      mutated_flag    = false
      web_mutated     = false
      mutated_paths   = []
      mutate_sub = container[:bus].subscribe("tool:after") do |ev|
        next unless %w[Write Edit Create FilePatch].include?(ev[:tool].to_s)
        mutated_flag = true
        path = ev[:path].to_s
        mutated_paths << path unless path.empty?
        web_mutated ||= path.include?("/MASTER/web/")
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

      # Post-turn standing orders: triad, autocommit, restart on web edits.
      if mutated_flag
        Thread.new do
          Thread.current.report_on_exception = false
          begin
            container[:bus].publish("triad:auto_start", reason: "post_chat_mutation")
            container[:command_registry].dig("triad")&.call(args: "deep .")
            container[:bus].publish("triad:auto_done")
          rescue StandardError => err
            container[:bus].publish("triad:auto_error", error: err.message)
          end
        end

        Thread.new do
          Thread.current.report_on_exception = false
          repo_root = Rails.root.join("..", "..").to_s
          msg = "auto: chat-turn mutation (#{mutated_paths.size} file(s))"
          _, status = Open3.capture2e("git", "-C", repo_root, "add", "-A")
          if status.success?
            _, st = Open3.capture2e("git", "-C", repo_root, "commit", "-m", msg)
            container[:bus].publish("autocommit:done", ok: st.success?)
          end
        rescue StandardError => err
          container[:bus].publish("autocommit:error", error: err.message)
        end

        if web_mutated
          Thread.new do
            Thread.current.report_on_exception = false
            _, status = Open3.capture2e("doas", "rcctl", "restart", "master")
            container[:bus].publish("master:restart", ok: status.success?)
          rescue StandardError => err
            container[:bus].publish("master:restart_error", error: err.message)
          end
        end
      end
    rescue => e
      sse.write("data: ERROR: #{e.message}\n\n")
      sse.write("data: [DONE]\n\n")
    ensure
      Fiber[:master_visitor] = nil
      begin
        tool_sub.call if defined?(tool_sub) && tool_sub
        mutate_sub.call if defined?(mutate_sub) && mutate_sub
      rescue StandardError
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
    voice = Master::Speech::DEFAULT_VOICE unless Master::Speech::VOICES.key?(voice)
    # :auto opts in to per-clause infer_style. Otherwise enforce whitelist.
    style = Master::Speech::DEFAULT_STYLE if style != :auto && !Master::Speech::STYLES.key?(style)

    bytes = Master::Speech.synthesize_bytes(text, voice: voice, style: style)
    if bytes && bytes.bytesize > 0
      send_data bytes, type: "audio/mpeg", disposition: "inline"
    else
      head :service_unavailable
    end
  rescue => e
    logger.error "TTS failed: #{e.message}"
    head :service_unavailable
  end
end
