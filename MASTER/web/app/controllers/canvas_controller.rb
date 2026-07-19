# frozen_string_literal: true

class CanvasController < ApplicationController
  # CSRF guarded by SameSite=Strict session cookie set in AuthTier.
  skip_before_action :verify_authenticity_token

  ALLOWED_TOPICS = %w[
    canvas:mood canvas:mode canvas:gesture canvas:idle canvas:tilt
    canvas:palette canvas:energy canvas:breath
    user:expression face:metrics
  ].freeze

  SEASON_TOPOLOGY = {
    "spring" => "ecology",
    "summer" => "face",
    "autumn" => "codebase",
    "winter" => "ecology",
  }.freeze

  # GET /canvas/topology?season=summer — seasonal accent hint for the pixel
  # field (wireVisionC/D in face_vision.bundle.js). No route existed for this
  # at all; the fetch always 404'd and was silently .catch()-guarded to an
  # empty seasonal event. topologies.yml has no seasonal concept, so this
  # derives a real one from the current date rather than the querystring
  # alone, falling back to it only if the param is one of the four seasons.
  def topology
    season = params[:season].to_s.presence_in(SEASON_TOPOLOGY.keys) || current_season
    render json: { season: season, id: SEASON_TOPOLOGY.fetch(season) }
  end

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
      tilt_y:     params[:tilt_y].to_f,
    }
    container[:bus].publish(:canvas_state, **payload) rescue nil
    head :accepted
  end

  private

  def current_season
    case Time.now.month
    when 3..5 then "spring"
    when 6..8 then "summer"
    when 9..11 then "autumn"
    else "winter"
    end
  end
end
