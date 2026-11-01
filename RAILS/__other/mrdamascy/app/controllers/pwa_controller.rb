# frozen_string_literal: true

class PwaController < ApplicationController
  # Web app manifest, served at /manifest.json (APP_SPEC §3/§7).
  def manifest
    render :manifest, layout: false
  end

  # The service worker must be scope-rooted: Service-Worker-Allowed opens "/"
  # so navigations to /offline and friends are controllable (APP_SPEC §6).
  # View template: pwa/service-worker.js.erb (hyphenated file name).
  def service_worker
    response.headers["Service-Worker-Allowed"] = "/"
    render "pwa/service-worker", layout: false
  end

  # Static friendly page the service worker precaches for offline navigations.
  def offline
  end
end
