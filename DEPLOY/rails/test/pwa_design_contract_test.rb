# frozen_string_literal: true

require "json"
require "minitest/autorun"

class PwaDesignContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber baibl blognet brgen bsdports hjerterom].freeze

  def test_all_apps_ship_generated_workbox_workers
    each_app do |app, root|
      worker = read(root, "app/views/pwa/service-worker.js")
      assert_includes worker, "Workbox 7.4.1 generated for #{app}"
      assert_includes worker, "__CACHE_VERSION__"
      assert_includes worker, "offline-forms"
      assert_includes worker, "notificationclick"
      assert_operator worker.bytesize, :>, 1_000
    end
  end

  def test_all_apps_expose_complete_pwa_routes
    each_app do |_app, root|
      routes = read(root, "config/routes.rb")
      javascript = read(root, "app/javascript/application.js", optional: true) +
        read(root, "app/assets/face.js", optional: true)
      assert_match(/get ["']offline["']/, routes)
      assert_match(/get ["']service-worker["']/, routes)
      assert_includes javascript, 'serviceWorker.register("/service-worker")'
    end
  end

  def test_all_manifests_are_installable
    each_app do |_app, root|
      manifest = JSON.parse(read(root, "app/views/pwa/manifest.json.erb"))
      assert_equal "/", manifest.fetch("start_url")
      assert_equal "/", manifest.fetch("scope")
      assert_includes %w[standalone fullscreen minimal-ui], manifest.fetch("display")
      assert_operator manifest.fetch("icons").size, :>=, 2
      assert manifest.fetch("theme_color").start_with?("#")
      assert manifest.fetch("background_color").start_with?("#")
    end
  end

  def test_all_layouts_apply_shared_visual_and_accessibility_baseline
    each_app do |_app, root|
      layout = read(root, "app/views/layouts/application.html.erb")
      assert_includes layout, "viewport-fit=cover"
      assert_includes layout, 'rel: "manifest"'
      assert_includes layout, "/styles/tokens.css"
      assert_match(/minimal-ui\.css|render "shared\/minimal_ui"/, layout)
      assert_match(/<main(?:\s|>)/, layout)
      assert_includes layout, "aria-label=\"Primary navigation\""
    end
  end

  private

  def each_app
    APPS.each { |app| yield app, File.join(ROOT, app) }
  end

  def read(root, relative, optional: false)
    File.read(File.join(root, relative))
  rescue Errno::ENOENT
    return "" if optional
    raise
  end
end
