# frozen_string_literal: true

require "minitest/autorun"

class MarketplaceCartContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  BRGEN = File.join(ROOT, "brgen")

  # marketplace became a mountable engine; its controllers, views and routes
  # moved to engines/marketplace/. Resolve either location so this contract
  # follows the code rather than the old layout.
  def brgen_read(relative)
    direct = File.join(BRGEN, relative)
    return File.read(direct) if File.file?(direct)

    vertical = relative[%r{\Aapp/(?:controllers|views|models)/([a-z_]+)/}, 1]
    engine = vertical && File.join(BRGEN, "engines", vertical, relative)
    assert engine && File.file?(engine), "missing brgen/#{relative}"
    File.read(engine)
  end

  def brgen_routes
    [File.join(BRGEN, "config/routes.rb"), *Dir.glob(File.join(BRGEN, "engines/*/config/routes.rb")).sort]
      .select { |f| File.file?(f) }.map { |f| File.read(f) }.join("\n")
  end

  def test_send_all_offers_is_wired
    routes = brgen_routes
    carts = brgen_read("app/controllers/marketplace/carts_controller.rb")
    view = brgen_read("app/views/marketplace/carts/show.html.erb")

    assert_includes routes, "post :send_offers"
    assert_includes carts, "def send_offers"
    # Inside the engine the helper is engine-local. `send_offers_marketplace_cart_path`
    # was the host-namespaced name before the extraction and resolves nowhere now.
    assert_includes view, "send_offers_cart_path"
    refute_includes view, "disabled: true"
    refute_includes view, "One-click checkout coming soon"
  end

  def test_cdn_assets_self_hosted
    dating = brgen_read("app/views/dating/home/index.html.erb")
    maps = brgen_read("app/views/maps/home/index.html.erb")
    amber = File.read(File.join(ROOT, "amber/app/views/layouts/application.html.erb"))

    # The dating landing loads css-doodle no longer (05f97fdd3 made discover the
    # landing page and dropped the heart), so only the CDN ban is left to hold.
    refute_includes dating, "cdn.jsdelivr.net/npm/css-doodle"
    assert_includes maps, "/vendor/maplibre-gl.js"
    refute_includes maps, "cdn.jsdelivr.net/npm/maplibre"
    refute_includes amber, "fonts.googleapis.com"
    assert File.file?(File.join(BRGEN, "public/vendor/maplibre-gl.js"))
    assert File.file?(File.join(ROOT, "amber/public/fonts/caprasimo-latin-400-normal.woff2"))
  end
end
