# frozen_string_literal: true

require "test_helper"
require_relative "../javascript/stimulus_node"

# The installable app: manifest, service worker and offline page.
class PwaControllerTest < ActionDispatch::IntegrationTest
  include StimulusNode

  def fetch_manifest
    get pwa_manifest_path
    assert_response :success
    JSON.parse(response.body)
  end

  test "the manifest names itself and every image it lists exists" do
    manifest = fetch_manifest

    assert_equal "/", manifest["id"]
    assert manifest["screenshots"].any?
    sources = (manifest["icons"] + manifest["screenshots"]).pluck("src")
    assert_empty sources.reject { |src| Rails.public_path.join(src.delete_prefix("/")).file? }
  end

  test "every manifest shortcut opens signed out" do
    fetch_manifest["shortcuts"].each do |shortcut|
      get shortcut["url"]
      assert_response :success, "#{shortcut['url']} must open without a login"
    end
  end

  test "every precached url answers" do
    PwaController::PRECACHE_URLS.each do |url|
      next if Rails.public_path.join(url.delete_prefix("/")).file?

      get url
      assert_response :success, url
    end
  end

  test "the service worker script is served to a plain browser fetch" do
    get pwa_service_worker_path

    assert_response :success
    assert_equal "/", response.headers["Service-Worker-Allowed"]
  end

  test "the cache version follows the assets instead of a hand-bumped name" do
    get pwa_service_worker_path
    version = response.body[/CACHE_VERSION = "damascy-(\w+)"/, 1]

    assert_match(/\A\h{12}\z/, version)
  end

  test "the menu opens offline from its last good copy" do
    get pwa_service_worker_path
    seen = run_node("service_worker_stage.mjs", response.body, "service_worker_offline_menu.mjs")

    assert_equal "live /", seen["online"]
    assert_equal "live /", seen["menu"], "offline, the menu is its last good copy"
    assert_equal "cached /offline", seen["loyalty"]
  end

  test "the service worker is registered once, not on every Turbo visit" do
    source = Rails.root.join("app/javascript/application.js").read.gsub(/^import .*\n/, "")
    seen = run_node("application_service_worker.mjs", source, "application_service_worker_visits.mjs")

    assert_equal [ "/service-worker.js" ], seen["registered"]
  end

  test "the offline retry reloads the url that failed" do
    get "/offline"
    assert_equal "retry", Nokogiri::HTML(response.body).at_css(".offline-page a")["data-controller"]
  end

  test "the browser chrome takes its colours from the design tokens" do
    tokens = ApplicationHelper::DESIGN_TOKENS
    manifest = fetch_manifest

    assert_equal [ tokens["--paper"], tokens["--surface-elevated"] ],
                 manifest.values_at("theme_color", "background_color")
    get root_path
    assert_equal tokens["--paper"], Nokogiri::HTML(response.body).at_css("meta[name=theme-color]")["content"]
  end

  test "the tab bar and hero draw their icons from shared partials" do
    seed_kitchen!
    get root_path
    page = Nokogiri::HTML(response.body)

    assert_equal 4, page.css(".tab-bar .tab-icon svg").size
    assert page.at_css(".hero-rating svg polygon")
    %w[app/views/layouts/application.html.erb app/views/menu/show.html.erb].each do |path|
      assert_not_includes Rails.root.join(path).read, "<svg", "#{path} draws an icon inline"
    end
  end

  test "the layout links the svg icon" do
    get root_path
    assert Nokogiri::HTML(response.body).at_css(%(link[rel=icon][type="image/svg+xml"][href="/icon.svg"]))
  end
end
