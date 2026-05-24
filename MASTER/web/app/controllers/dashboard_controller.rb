# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
  end

  def live
    c = container
    render json: {
      events: c[:session].respond_to?(:messages) ? c[:session].messages.last(10) : [],
      model: c[:agent].model.to_s,
      open_breakers: c[:breaker].respond_to?(:open_models) ? c[:breaker].open_models : []
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :service_unavailable
  end
end