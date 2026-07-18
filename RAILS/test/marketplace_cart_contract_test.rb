# frozen_string_literal: true

require "minitest/autorun"

class MarketplaceCartContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  BRGEN = File.join(ROOT, "brgen")

  def test_send_all_offers_is_wired
    routes = File.read(File.join(BRGEN, "config/routes.rb"))
    carts = File.read(File.join(BRGEN, "app/controllers/marketplace/carts_controller.rb"))
    view = File.read(File.join(BRGEN, "app/views/marketplace/carts/show.html.erb"))

    assert_includes routes, "post :send_offers"
    assert_includes carts, "def send_offers"
    assert_includes view, "send_offers_marketplace_cart_path"
    refute_includes view, "disabled: true"
    refute_includes view, "One-click checkout coming soon"
  end

  def test_amber_jobs_are_not_placeholders
    rembg = File.read(File.join(ROOT, "amber/app/jobs/remove_background_job.rb"))
    seg = File.read(File.join(ROOT, "amber/app/jobs/segment_garment_image_job.rb"))
    assert_includes rembg, "PostproProcessor"
    assert_includes seg, "PostproProcessor"
    refute_includes rembg, "placeholder"
    refute_includes seg, "placeholder"
  end

  def test_cdn_assets_self_hosted
    dating = File.read(File.join(BRGEN, "app/views/dating/home/index.html.erb"))
    maps = File.read(File.join(BRGEN, "app/views/maps/home/index.html.erb"))
    amber = File.read(File.join(ROOT, "amber/app/views/layouts/application.html.erb"))

    assert_includes dating, "/vendor/css-doodle.min.js"
    refute_includes dating, "cdn.jsdelivr.net/npm/css-doodle"
    assert_includes maps, "/vendor/maplibre-gl.js"
    refute_includes maps, "cdn.jsdelivr.net/npm/maplibre"
    refute_includes amber, "fonts.googleapis.com"
    assert File.file?(File.join(BRGEN, "public/vendor/css-doodle.min.js"))
    assert File.file?(File.join(BRGEN, "public/vendor/maplibre-gl.js"))
    assert File.file?(File.join(ROOT, "amber/public/fonts/caprasimo-latin-400-normal.woff2"))
  end
end
