# frozen_string_literal: true

require "json"

class DashboardController < ApplicationController
  PANEL_TAIL_BYTES = 16 * 1024
  PANEL_RECENT_LINES = 8
  PROPOSAL_EXCERPT_BYTES = 400

  def index
    @tier = request.env["master.tier"].to_s
    render layout: false
  end

  # One fetcher, the dashboard page, which is the normal shape for a JSON action. The dashboard
  # stays out of config/face_assets.yml: it loads no face module, only the standalone
  # /dashboard_live.js poller and /face.css; the face manifest remains chat-specific.
  def live
    c = container
    return render(json: { error: "warming up" }, status: :service_unavailable) unless c

    root = Master::ROOT
    render json: mission_payload(c, root)
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "Dashboard.live")
    render json: { error: "dashboard unavailable" }, status: :service_unavailable
  end

  private

  def mission_payload(c, root)
    session = c[:session]
    agent = c[:agent]
    logging = c[:logging]
    bus_events = logging.respond_to?(:dmesg) ? logging.dmesg(20).to_s.lines.map(&:chomp) : []
    pressure = Master::Trace::ContextPressure.snapshot(session:)
    {
      events: session.respond_to?(:messages) ? session.messages.last(10) : [],
      bus_events:,
      model: agent.model.to_s,
      mission: Master::Fix::Mission.current(root:),
      tokens: pressure[:tokens],
      cost: session.respond_to?(:cost) ? session.cost : 0.0,
      open_breakers: c[:breaker].respond_to?(:open_models) ? c[:breaker].open_models : [],
      agent_pool: c[:agent_pool]&.active_count || 0,
      rtk: Master::Io::OutputFilter.stats(root),
      rsi_inbox: rsi_inbox(root),
      active_plan: Master::Ground::ActivePlan.read(root),
      skills: Array(c[:skills]&.loaded).pluck(:name),
      context_pressure: pressure,
      provider_health: provider_health(c),
      cache_efficiency: Master::Trace::CacheEfficiency.snapshot,
      model_quota: Master::Io::ModelQuota.snapshot,
      repair_queue: repair_queue(root),
    }
  end

  def provider_health(c)
    breaker = c[:breaker]
    open = breaker.respond_to?(:open_models) ? Array(breaker.open_models) : []
    {
      open_breakers: open,
      status: open.empty? ? "healthy" : "degraded",
      agent_pool: c[:agent_pool]&.active_count || 0,
    }
  end

  # Both file panels read a fixed candidate list, skip whatever this checkout
  # does not have, and describe each hit. An unreadable file drops the whole
  # panel rather than the request: a dashboard missing one card still loads.
  def file_panel(root, relative_paths, context:)
    relative_paths.filter_map do |rel|
      path = File.join(root, rel)
      next unless File.file?(path)

      yield(rel, path)
    end
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context:)
    []
  end

  def repair_queue(root)
    file_panel(root, %w[runtime/failures.jsonl runtime/repair_queue.json runtime/telemetry/failures.jsonl],
               context: "Dashboard.log_listing") do |rel, path|
      { path: rel, count: File.size(path), recent: recent_lines(path) }
    end
  end

  def rsi_inbox(root)
    file_panel(root, %w[data/proposals.yml],
               context: "Dashboard.file_excerpts") do |rel, path|
      { path: rel, bytes: File.size(path), excerpt: bounded_excerpt(path) }
    end
  end

  # This endpoint refreshes frequently; display panels must never read whole
  # append-only logs or a growing proposals file merely to render a short preview.
  def recent_lines(path)
    File.open(path, "rb") do |file|
      size = file.stat.size
      offset = [ size - PANEL_TAIL_BYTES, 0 ].max
      file.seek(offset)
      tail = file.read(PANEL_TAIL_BYTES).to_s
      if offset.positive?
        boundary = tail.index("\n")
        tail = boundary ? tail[(boundary + 1)..] : ""
      end
      tail.force_encoding(Encoding::UTF_8).scrub("?").lines(chomp: true).last(PANEL_RECENT_LINES)
    end
  end

  def bounded_excerpt(path)
    File.open(path, "rb") do |file|
      file.read(PROPOSAL_EXCERPT_BYTES).to_s.force_encoding(Encoding::UTF_8).scrub("?")
    end
  end
end
