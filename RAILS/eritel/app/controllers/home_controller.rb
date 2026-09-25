# frozen_string_literal: true

class HomeController < ActionController::Base
  def show
    render json: {
      app: "eritel",
      namespace: ".er",
      registry_provider: Rails.application.config.x.registry_provider,
      message: "EriTel partner platform reference deployment"
    }
  end
end
