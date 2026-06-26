# frozen_string_literal: true

class CanvasController < ApplicationController
  # CSRF guarded by SameSite=Strict session cookie set in AuthTier.
  skip_before_action :verify_authenticity_token

  ALLOWED_TOPICS = %w[
    canvas:mood canvas:mode canvas:gesture canvas:idle canvas:tilt
    canvas:palette canvas:energy canvas:breath
    user:expression face:metrics
  ].freeze

  def post_event
    topic = params.require(:topic).to_s
    return head(:unprocessable_entity) unless ALLOWED_TOPICS.include?(topic)
    raw = params.fetch(:payload, {}).to_unsafe_h
    if topic == "user:expression"
      expression = raw.slice("source", "valence", "arousal", "attention", "pressure").transform_keys(&:to_sym)
      container[:bus].publish("user:expression", expression: expression, source: expression[:source]) rescue nil
      return head :accepted
    end
    if topic == "face:metrics"
      metrics = raw.slice("face_boot_ms", "particle_worker_alive", "feature_count", "bench_fps").transform_keys(&:to_sym)
      Rails.cache.write("face:metrics:#{request.remote_ip}", metrics, expires_in: 5.minutes)
      return head :accepted
    end

    payload = raw.slice(
      "mood", "mode", "idle", "energy", "palette", "tilt_x", "tilt_y"
    ).transform_keys(&:to_sym)
    container[:bus].publish(topic, **payload) rescue nil
    head :accepted
  end

  def state
    payload = {
      mood:       params[:mood].to_s,
      mode:       params[:mode].to_s,
      idle_s:     params[:idle].to_i,
      palette:    params[:palette].to_i,
      confidence: params[:confidence].to_f,
      tilt_x:     params[:tilt_x].to_f,
      tilt_y:     params[:tilt_y].to_f
    }
    container[:bus].publish(:canvas_state, **payload) rescue nil
    head :accepted
  end
end
