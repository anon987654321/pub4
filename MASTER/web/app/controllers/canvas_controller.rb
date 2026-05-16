# frozen_string_literal: true

class CanvasController < ApplicationController
  ALLOWED_TOPICS = %w[
    canvas:mood canvas:mode canvas:gesture canvas:idle canvas:tilt
    canvas:palette canvas:energy canvas:breath
  ].freeze

  def post_event
    topic = params.require(:topic).to_s
    return head(:unprocessable_entity) unless ALLOWED_TOPICS.include?(topic)
    payload = params.fetch(:payload, {}).to_unsafe_h.slice(
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
