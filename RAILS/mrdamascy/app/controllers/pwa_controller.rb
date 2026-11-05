# frozen_string_literal: true

class PwaController < ApplicationController
  # What the service worker caches on install: the offline page and the
  # brand marks it draws.
  PRECACHE_URLS = [ "/offline", "/icon-192.png", "/icon-512.png", "/logo.svg" ].freeze

  # A browser fetches the worker script with a plain GET, which forgery
  # protection refused as cross-origin JavaScript (422), so the worker never
  # installed. The script carries no secrets.
  skip_forgery_protection only: :service_worker

  # Web app manifest, served at /manifest.json (APP_SPEC §3/§7).
  def manifest
    render :manifest, layout: false
  end

  # The service worker must be scope-rooted: Service-Worker-Allowed opens "/"
  # so navigations to /offline and friends are controllable (APP_SPEC §6).
  # View template: pwa/service-worker.js.erb (hyphenated file name).
  def service_worker
    response.headers["Service-Worker-Allowed"] = "/"
    @cache_version = cache_version
    render "pwa/service-worker", layout: false
  end

  # Static friendly page the service worker precaches for offline navigations.
  def offline
  end

  private

  # Changes whenever a digested stylesheet or script, or a precached public
  # file, changes — no hand-bumped version to forget.
  def cache_version
    marks = PRECACHE_URLS.filter_map { |url| Rails.public_path.join(url.delete_prefix("/")) }.select(&:file?)
    Digest::SHA256.hexdigest(
      [ helpers.asset_path("application.css"), helpers.asset_path("application.js"), *marks.map(&:read) ].join("\n")
    ).first(12)
  end
end
