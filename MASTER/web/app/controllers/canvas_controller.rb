# frozen_string_literal: true

# Sink for closed-loop UI signals. Chat client posts mood/mode/idle/etc. and
# raw bus events; we re-emit on the in-process EventBus so prompt-builder
# can pick up user-state context. No view, no SSE.
class CanvasController < ApplicationController
  def post_event
    topic   = params.require(:topic)
    payload = params.fetch(:payload, {}).permit!.to_h
    Master::Trace::EventBus.instance.publish(topic, **payload.transform_keys(&:to_sym)) rescue nil
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
    Master::Trace::EventBus.instance.publish(:canvas_state, **payload) rescue nil
    head :accepted
  end
end
