# frozen_string_literal: true

module Rails
  class PwaController < ApplicationController
    CACHE_VERSION_PLACEHOLDER = "__CACHE_VERSION__"

    def manifest
      http_cache_forever(public: false) do
        render template: "pwa/manifest", formats: :json
      end
    end

    def service_worker
      http_cache_forever(public: false) do
        render js: service_worker_source, content_type: "application/javascript"
      end
    end

    def offline
      render partial: "shared/offline_page", layout: "application", locals: { app_name: "BSDports", storage_key: "bsdports" }
    end

    private

    def service_worker_source
      render_to_string(template: "pwa/service-worker", layout: false)
        .gsub(CACHE_VERSION_PLACEHOLDER, ENV.fetch("CACHE_VERSION", "v2"))
    end
  end
end
