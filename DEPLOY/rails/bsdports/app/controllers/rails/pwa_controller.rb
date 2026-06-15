# frozen_string_literal: true

module Rails
  class PwaController < ApplicationController
    def manifest
      render template: "pwa/manifest", formats: :json
    end

    def service_worker
      render template: "pwa/service-worker", content_type: "application/javascript"
    end

    def offline
      render partial: "shared/offline_page", locals: { app_name: "BSD Ports", storage_key: "bsdports" }
    end
  end
end
