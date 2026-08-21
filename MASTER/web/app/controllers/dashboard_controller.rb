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

  def repair_queue(root)
    paths = %w[runtime/failures.jsonl runtime/repair_queue.json runtime/telemetry/failures.jsonl]
    paths.filter_map do |rel|
      path = File.join(root, rel)
      next unless File.file?(path)

      lines = File.readlines(path).map(&:chomp).last(8)
      { path: rel, count: File.size(path), recent: lines }
    end
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "Dashboard.log_listing")
    []
  end

  def rsi_inbox(root)
    paths = %w[runtime/improvements.md runtime/rsi_improvements.md runtime/soul_proposals.md]
    paths.filter_map do |rel|
      path = File.join(root, rel)
      next unless File.file?(path)

      { path: rel, bytes: File.size(path), excerpt: File.read(path)[0, 400] }
    end
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "Dashboard.file_excerpts")
    []
  end
end
