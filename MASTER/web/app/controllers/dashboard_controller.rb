# frozen_string_literal: true

require "json"

class DashboardController < ApplicationController
  def index
    @tier = request.env["master.tier"].to_s
    render layout: false
  end

  def live
    c = container
    return render(json: { error: "warming up" }, status: :service_unavailable) unless c

    root = Master::ROOT
    render json: mission_payload(c, root)
  rescue StandardError => e
    render json: { error: e.message }, status: :service_unavailable
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
      tokens: pressure[:tokens],
      cost: session.respond_to?(:cost) ? session.cost : 0.0,
      open_breakers: c[:breaker].respond_to?(:open_models) ? c[:breaker].open_models : [],
      agent_pool: c[:agent_pool]&.active_count || 0,
      rtk: Master::Io::OutputFilter.stats(root),
      rsi_inbox: rsi_inbox(root),
      active_plan: Master::Ground::ActivePlan.read(root),
      skills: Array(c[:skills]&.loaded).map { |s| s[:name] },
      context_pressure: pressure,
      provider_health: provider_health(c),
      cache_efficiency: Master::Trace::CacheEfficiency.snapshot,
      model_quota: Master::Ground::ModelQuota.snapshot,
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
      { path: rel, count: File.size(path), recent: File.readlines(path).map(&:chomp).last(8) }
    end
  end

  def rsi_inbox(root)
    file_panel(root, %w[runtime/improvements.md runtime/rsi_improvements.md runtime/soul_proposals.md],
               context: "Dashboard.file_excerpts") do |rel, path|
      { path: rel, bytes: File.size(path), excerpt: File.read(path)[0, 400] }
    end
  end
end
