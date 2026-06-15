# frozen_string_literal: true
# AN208: Pundit authorization helpers

module Shared
  module PunditAuthorization
    extend ActiveSupport::Concern

    included do
      include Pundit::Authorization if defined?(Pundit)
      rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized if defined?(Pundit)
    end

    private

    def user_not_authorized
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: "Not authorized" }
        format.turbo_stream { head :forbidden }
        format.json { render json: { error: "forbidden" }, status: :forbidden }
      end
    end
  end
end