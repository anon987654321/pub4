# frozen_string_literal: true

require "digest"
require "json"
require "open3"

class ChatController < ApplicationController
  # CSRF guarded by SameSite=Strict session cookie set in AuthTier.
  skip_before_action :verify_authenticity_token, only: :command
  # Face shell renders immediately; container finishes booting in the background (~90s on VPS).
  skip_before_action :require_container!, only: :index

  def index
    c = container
    @model = c&.[](:agent)&.model.to_s.split("/").last.presence || "booting"
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
    return render(json: { error: "warming up" }, status: :service_unavailable) unless c

    repo_root = Rails.root.join("..").to_s
    out, = Open3.capture2e("git", "-C", repo_root, "status", "--porcelain")
    dirty = out.lines.count
    open_models = c[:breaker].respond_to?(:open_models) ? c[:breaker].open_models : []
    cache = Master::Trace::CacheEfficiency.snapshot
    quota = Master::Ground::ModelQuota.snapshot[:exhausted]
    render json: {
      model:            c[:agent].model.to_s.split("/").last,
      tokens:           c[:session].respond_to?(:token_est) ? c[:session].token_est : 0,
      cost:             "$%.4f" % (c[:session].respond_to?(:cost) ? c[:session].cost : 0.0),
      uptime:           ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - start_ms),
      repo_dirty_count: dirty,
      open_breakers:    open_models,
      tier:             request.env["master.tier"].to_s,
      cache_efficiency: cache[:efficiency_pct],
      model_quota:      quota
    }
  end

  def history
    messages = container[:session].messages.last(200).map { |m| { role: m[:role], content: m[:content].to_s[0, 2000] } }
    render json: messages
  end

  def skills
    loaded = container[:skills]&.loaded || []
    render json: loaded.map { |s| { name: s[:name], description: s[:description], triggers: s[:triggers] } }
  rescue StandardError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def command
    cmd = (params[:command] || JSON.parse(request.body.read)["command"]).to_s.strip
    if cmd.start_with?("/unlock ")
      pw = cmd.sub(/^\/unlock\s+/, "").strip
      token = ENV["MASTER_WEB_TOKEN"].to_s
      if token.empty? || pw != token
        render(json: { output: "unlock denied" }, status: 401) and return
      end
      cookies[:master_unlocked] = { value: "1", expires: 1.year.from_now, secure: true, httponly: true, same_site: :strict }
      render(json: { output: "unlocked — full tool access enabled." }) and return
    end
    return head(:forbidden) if visitor? && cmd.start_with?("/")

    result = container[:gateway].receive(channel: :cli, message: cmd)
    value = result.ok? ? result.value! : nil
    output = value.is_a?(Hash) ? (value[:rendered] || value.to_s) : (value || result.message)
    client_actions = value.is_a?(Hash) ? Array(value[:client_actions]) : []
    render json: { output: output, client_actions: client_actions }
  rescue StandardError => e
    render json: { output: "Error: #{e.message}" }, status: 500
  end

  def research
    n = params[:n].to_i.clamp(1, 30)
    n = 10 if n.zero?
    require "net/http"
    require "uri"
    cats = %w[cs.AI cs.LG cs.CL cs.NE q-bio physics.gen-ph astro-ph]
    q = cats.map { |c| "cat:#{c}" }.join("+OR+")
    uri = URI("https://export.arxiv.org/api/query?search_query=#{q}&sortBy=submittedDate&sortOrder=descending&max_results=#{n}")
    body = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 6) { |h| h.get(uri.request_uri).body }
    items = body.to_s.scan(/<entry>(.*?)<\/entry>/m).map do |entry|
      entry = entry.first
      t = entry[/<title>(.*?)<\/title>/m, 1].to_s.gsub(/\s+/, " ").strip
      s = entry[/<summary>(.*?)<\/summary>/m, 1].to_s.gsub(/\s+/, " ").strip.split(/(?<=[.!?])\s+/).first(2).to_a.join(" ")
      next if t.empty?
      "#{t}. #{s}".slice(0, 480)
    end.compact
    render json: { items: items }
  rescue StandardError => e
    web_logger.warn("research failed: #{e.class}: #{e.message}")
    render json: { items: [] }
  end

  def enhance
    msg = params[:message].to_s.strip
    return render(json: { changed: false }) if msg.empty?

    result = Master::Now::Stages::Enhance.run(msg, agent: container[:agent], event_bus: container[:bus])
    render json: result
  rescue StandardError => e
    render json: { changed: false, error: e.message }
  end

  def photo
    status, payload = ImagePresenter.new(logger: web_logger).store(params[:photo])
    render json: payload, status: status
  end

  def message
    mp = message_params
    input = mp[:message].to_s.strip
    return head(:bad_request) if input.empty?
    return head(:forbidden) if visitor? && input.start_with?("/")
    return stream_smoke_reply(input) if smoke_chat_message?(input)

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    ChatService.new(
      container: container,
      params: mp,
      stream: response.stream,
      logger: web_logger,
      tier: request.env["master.tier"].to_s,
      unlocked: cookies[:master_unlocked].to_s == "1",
      author: cookies[:master_author].to_s.present?
    ).call
  end

  private

  def message_params
    params.permit(:message, :state, :pre_enhanced, :voice, :image_token, image: %i[data mime name])
  end

  def web_logger
    @web_logger ||= WebEventLogger.new(container[:bus])
  end

  SMOKE_CHAT_MESSAGES = %w[ping pong health up].freeze

  def smoke_chat_message?(text)
    SMOKE_CHAT_MESSAGES.include?(text.to_s.strip.downcase)
  end

  def stream_smoke_reply(input)
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    body = case input.to_s.strip.downcase
           when "ping" then "pong"
           when "pong" then "ping"
           else "ok"
           end
    response.stream.write(": connected\n\n")
    response.stream.write("data: #{body}\n\n")
    response.stream.write("data: [DONE]\n\n")
  ensure
    response.stream.close
  end

end
