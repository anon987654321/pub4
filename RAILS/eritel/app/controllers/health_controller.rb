# frozen_string_literal: true

class HealthController < ActionController::API
  def show
    render json: {
      app: "eritel",
      status: "ok",
      registry_provider: Rails.application.config.x.registry_provider
    }
  end
end
