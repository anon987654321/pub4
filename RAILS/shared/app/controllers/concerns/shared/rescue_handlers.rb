# frozen_string_literal: true

module Shared
  # Rails style guide: centralized HTTP error handling in ApplicationController.
  module RescueHandlers
    extend ActiveSupport::Concern

    included do
      rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
      rescue_from ActionController::ParameterMissing, with: :parameter_missing
      rescue_from Pundit::NotAuthorizedError, with: :not_authorized if defined?(Pundit)
    end

    private

    def record_not_found
      respond_to do |format|
        format.html { head :not_found }
        format.json { render json: { error: "not_found" }, status: :not_found }
        format.turbo_stream { head :not_found }
      end
    end

    def parameter_missing(exception)
      respond_to do |format|
        format.html { head :bad_request }
        format.json { render json: { error: "parameter_missing", param: exception.param }, status: :bad_request }
        format.turbo_stream { head :bad_request }
      end
    end

    def not_authorized
      respond_to do |format|
        format.html { head :forbidden }
        format.json { render json: { error: "forbidden" }, status: :forbidden }
        format.turbo_stream { head :forbidden }
      end
    end
  end
end