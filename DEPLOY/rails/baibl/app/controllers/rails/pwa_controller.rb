# frozen_string_literal: true

module Rails
  class PwaController < ApplicationController
    CACHE_VERSION_PLACEHOLDER = "__CACHE_VERSION__"

    def manifest
      render template: "pwa/manifest", formats: :json
    end

    def service_worker
      render js: service_worker_source, content_type: "application/javascript"
    end

    def offline
      render partial: "shared/offline_page", locals: { app_name: "Baibl", storage_key: "baibl" }
    end

    private

    def service_worker_source
      render_to_string(template: "pwa/service-worker", layout: false)
        .gsub(CACHE_VERSION_PLACEHOLDER, ENV.fetch("CACHE_VERSION", "v2"))
    end
  end
end
