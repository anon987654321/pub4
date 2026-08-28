# frozen_string_literal: true

require "json"

class RuntimeController < ApplicationController
  skip_before_action :require_container!

  def boot_config
    render_runtime_json(Master::Ground::RuntimeCatalog.web_boot_payload)
  end

  def topologies
    data = Master.load_yaml(Master.data_path("topologies.yml"), default: {})
    render_runtime_json(data)
  end

  def status
    c = container
    model = c&.[](:agent)&.model.to_s.split("/").last.presence || "booting"
    metrics = Rails.cache.read("face:metrics:#{request.remote_ip}") || {}
    render_runtime_json({
      ready: !c.nil?,
      model:,
      uptime_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - start_ms),
      tier: request.env["master.tier"].to_s,
      build: ENV.fetch("CACHE_VERSION", "dev"),
      face_boot_ms: metrics[:face_boot_ms] || metrics["face_boot_ms"],
      particle_worker_alive: metrics[:particle_worker_alive] || metrics["particle_worker_alive"],
    })
  end

  private

  def render_runtime_json(payload)
    render body: JSON.generate(payload), content_type: "application/json"
  end
end
