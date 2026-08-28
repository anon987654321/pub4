# frozen_string_literal: true

require "digest"
require "json"
require "open3"

class ChatController < ApplicationController
  include ActionController::Live

  # CSRF guarded by SameSite=Strict session cookie set in AuthTier.
  skip_before_action :verify_authenticity_token, only: :command
  before_action :require_same_origin!, only: :command
  # Face shell renders immediately; container finishes booting in the background (~90s on VPS).
  # Metrics returns 401/503 JSON — must not hit the HTML warming gate first.
  skip_before_action :require_container!, only: %i[index metrics metrics_prometheus]

  def index
    c = container
    # Mint the conversation cookie here rather than on the first chat POST.
    # That POST is an SSE stream, and a Set-Cookie added after the response has
    # begun committing is a cookie the browser never sees — the visitor would
    # get a fresh transcript on every turn. A plain HTML render has no such
    # problem, and every chat begins with this page.
    conversation_id
    @model = c&.[](:agent)&.model.to_s.split("/").last.presence || "booting"
    @tier  = request.env["master.tier"].to_s
    @profile = face_profile
    @container_ready = !c.nil?
    render layout: false
  end

  def dmesg
    out, = Open3.capture2e("dmesg")
    lines = out.lines.first(20).map(&:chomp)
    render json: { lines: }
  end

  def metrics
    c = container
    return render(json: { error: "warming up" }, status: :service_unavailable) unless c

    render json: metrics_payload(c)
  end

  def metrics_prometheus
    c = container
    unless c
      return render(plain: "# HELP master_up 1 if ready\nmaster_up 0\n", status: :service_unavailable,
                    content_type: "text/plain; version=0.0.4")
    end

    data = metrics_payload(c)
    lines = [
      "# HELP master_up 1 if ready",
      "master_up 1",
      "# HELP master_tokens Context tokens",
      "master_tokens #{data[:tokens]}",
      "# HELP master_cost_usd Session cost USD",
      "master_cost_usd #{data[:cost_usd]}",
      "# HELP master_repo_dirty_count Git dirty file count",
      "master_repo_dirty_count #{data[:repo_dirty_count]}",
      "# HELP master_cache_efficiency_pct Cache hit efficiency",
      "master_cache_efficiency_pct #{data[:cache_efficiency]}",
    ]
    render plain: lines.join("\n") + "\n", content_type: "text/plain; version=0.0.4"
  end

  def history
    c = container
    return render(json: { error: "warming up" }, status: :service_unavailable) unless c

    # Keyed, or an authenticated operator opening the page is served whatever
    # the :local partition happens to hold rather than their own transcript.
    messages = c[:session].messages(conversation_id)
                          .last(200).map { |m| { role: m[:role], content: m[:content].to_s[0, 2000] } }
    render json: messages
  end

  def skills
    c = container
    return render(json: { error: "warming up" }, status: :service_unavailable) unless c

    loaded = c[:skills]&.loaded || []
    render json: loaded.map { |s| { name: s[:name], description: s[:description], triggers: s[:triggers] } }
  rescue StandardError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def command
    cmd = (params[:command] || JSON.parse(request.body.read)["command"]).to_s.strip
    if cmd.start_with?("/unlock ")
      pw = cmd.sub(/^\/unlock\s+/, "").strip
      token = MasterWebToken.read
      if token.empty? || pw.bytesize != token.bytesize || !Rack::Utils.secure_compare(pw, token)
        render(json: { output: "unlock denied" }, status: 401) and return
      end
      set_unlock_cookie
      render(json: { output: "unlocked — full tool access enabled." }) and return
    end
    if (code = pair_redeem_arg(cmd))
      if pair_redeem_limited?
        render(json: { output: "pair: too many tries — wait a minute" }, status: :too_many_requests)
        return
      end
      result = Master::Ground::Pairing.redeem(code)
      if result
        set_pair_cookie(result[:token])
        render(json: { output: Master::Ground::Pairing.redeem_notice(result) })
      else
        render(json: { output: "pair: invalid or expired code" }, status: :unprocessable_entity)
      end
      return
    end
    return head(:forbidden) if visitor?

    with_master_fiber(unlocked: unlocked?) do
      result = container[:gateway].receive(channel: :cli, message: cmd)
      value = result.ok? ? result.value! : nil
      output = value.is_a?(Hash) ? (value[:rendered] || value.to_s) : (value || result.message)
      client_actions = value.is_a?(Hash) ? Array(value[:client_actions]) : []
      render json: { output:, client_actions: }
    end
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
    render json: { items: }
  rescue StandardError => e
    web_logger.warn("research failed: #{e.class}: #{e.message}")
    render json: { items: [] }
  end

  def enhance
    msg = params[:message].to_s.strip
    return render(json: { changed: false }) if msg.empty?

    # Same fiber flags as /chat/message. Without them Tool::Profile.current is
    # :full, so a visitor enhance turn advertised ReadFile and could have the
    # model open .master/config.yml for the web token.
    with_master_fiber(unlocked: unlocked?) do
      result = Master::CLI::Stages::Enhance.run(msg, agent: container[:agent], event_bus: container[:bus])
      render json: result
    end
  rescue StandardError => e
    render json: { changed: false, error: e.message }
  end

  def photo
    status, payload = ImagePresenter.new(logger: web_logger).store(params[:photo])
    render json: payload, status:
  end

  def message
    mp = message_params
    input = mp[:message].to_s.strip
    return head(:bad_request) if input.empty?
    return redeem_pair_from_chat(input) if visitor? && pair_redeem_arg(input)
    return head(:forbidden) if visitor? && input.start_with?("/")
    return stream_smoke_reply(input) if smoke_chat_message?(input)

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    ChatService.new(
      container:,
      params: mp,
      stream: response.stream,
      logger: web_logger,
      tier: request.env["master.tier"].to_s,
      unlocked: unlocked?,
      author: false,
      paired: pairing_active?,
      pair_token: cookies[:master_paired].to_s,
      conversation: conversation_id,
    ).call
  rescue IOError, ActionController::Live::ClientDisconnected
    nil
  ensure
    response.stream.close rescue nil
  end

  private

  def pair_redeem_arg(cmd)
    return unless cmd.to_s.match?(%r{\A/pair(?:\s|\z)})

    rest = cmd.to_s.sub(%r{\A/pair\s*}, "")
    return if rest.empty? || rest.match?(/\A(issue|list|revoke|status)\b/i)

    rest.split.first
  end

  def redeem_pair_from_chat(input)
    if pair_redeem_limited?
      stream_plain("pair: too many tries — wait a minute")
      return
    end

    result = Master::Ground::Pairing.redeem(pair_redeem_arg(input))
    body = if result
             set_pair_cookie(result[:token])
             Master::Ground::Pairing.redeem_notice(result)
           else
             "pair: invalid or expired code"
           end
    stream_plain(body)
  end

  def stream_plain(body)
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    response.stream.write(": connected\n\n")
    response.stream.write("data: #{body}\n\n")
    response.stream.write("data: [DONE]\n\n")
  ensure
    response.stream.close
  end

  def message_params
    params.permit(:message, :state, :pre_enhanced, :voice, :image_token, image: %i[data mime name])
  end

  def metrics_payload(c)
    repo_root = Rails.root.join("..").to_s
    out, = Open3.capture2e("git", "-C", repo_root, "status", "--porcelain")
    dirty = out.lines.count
    open_models = c[:breaker].respond_to?(:open_models) ? c[:breaker].open_models : []
    cache = Master::Trace::CacheEfficiency.snapshot
    quota = Master::Ground::ModelQuota.snapshot[:exhausted]
    cost = c[:session].respond_to?(:cost) ? c[:session].cost : 0.0
    {
      model:            c[:agent].model.to_s.split("/").last,
      tokens:           c[:session].respond_to?(:token_est) ? c[:session].token_est : 0,
      cost:             "$%.4f" % cost,
      cost_usd:         cost,
      uptime:           ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - start_ms),
      repo_dirty_count: dirty,
      open_breakers:    open_models,
      tier:             request.env["master.tier"].to_s,
      cache_efficiency: cache[:efficiency_pct],
      model_quota:      quota,
    }
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
