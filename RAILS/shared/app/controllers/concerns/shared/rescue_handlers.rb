# frozen_string_literal: true

module Shared
  # Centralised HTTP error handling for every app.
  #
  # The HTML branches render a page rather than answering `head :not_found`,
  # which paints a blank white screen with a status code and nothing else.
  # Rails serves each app's styled public/404.html only for *unhandled*
  # exceptions, so anything caught here has to render its own.
  module RescueHandlers
    extend ActiveSupport::Concern

    included do
      rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
      rescue_from ActionController::ParameterMissing, with: :parameter_missing
      rescue_from Pundit::NotAuthorizedError, with: :not_authorized if defined?(Pundit)
    end

    private

    def record_not_found
      render_http_error(:not_found, "not_found")
    end

    def parameter_missing(exception)
      render_http_error(:bad_request, "parameter_missing", param: exception.param)
    end

    def not_authorized
      render_http_error(:forbidden, "forbidden")
    end

    # 422.html and 500.html are not shipped by every app, so the page is used
    # when it exists and a bare head is the fallback — never a 200 with an error
    # body, and never a missing-template 500 raised from an error handler.
    def render_http_error(status, error, **details)
      respond_to do |format|
        format.html { render_static_error_page(status) }
        format.json { render json: { error: }.merge(details), status: }
        format.turbo_stream { head status }
        format.any { head status }
      end
    end

    def render_static_error_page(status)
      page = Rails.public_path.join("#{Rack::Utils.status_code(status)}.html")
      return head(status) unless page.file?

      render html: page.read.html_safe, status:, layout: false
    end
  end
end
