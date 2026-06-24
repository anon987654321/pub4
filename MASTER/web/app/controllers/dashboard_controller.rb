# frozen_string_literal: true

require "json"

class DashboardController < ApplicationController
  def index
    @tier = request.env["master.tier"].to_s
    render layout: false
  end

  def live
    c = container
    root = Rails.root.join("..", "..").to_s
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
    {
      events: session.respond_to?(:messages) ? session.messages.last(10) : [],
      bus_events: bus_events,
      model: agent.model.to_s,
      tokens: session.respond_to?(:token_est) ? session.token_est : 0,
      cost: session.respond_to?(:cost) ? session.cost : 0.0,
      open_breakers: c[:breaker].respond_to?(:open_models) ? c[:breaker].open_models : [],
      agent_pool: c[:agent_pool]&.active_count || 0,
      rtk: Master::Reach::OutputFilter.stats(root),
      rsi_inbox: rsi_inbox(root),
      active_plan: Master::Ground::ActivePlan.read(root),
      skills: Array(c[:skills]&.loaded).map { |s| s[:name] }
    }
  end

  def rsi_inbox(root)
    paths = %w[runtime/improvements.md runtime/rsi_improvements.md runtime/soul_proposals.md]
    paths.filter_map do |rel|
      path = File.join(root, rel)
      next unless File.file?(path)

      { path: rel, bytes: File.size(path), excerpt: File.read(path)[0, 400] }
    end
  rescue StandardError
    []
  end
end