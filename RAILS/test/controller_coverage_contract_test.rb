# frozen_string_literal: true

require "minitest/autorun"

# Static contract: state-mutating vertical controllers exist with the actions
# apps.yml claims are done. Complements model_coverage_contract_test.rb.
#
# Read the name carefully: this is not test coverage. Nothing here boots Rails or
# calls a method, so every assertion passes against a body of `raise` — it checks
# that apps.yml is not claiming a controller or action that does not exist, which is
# worth having and is all it is. The actual "does this have a test" number lives in
# coverage_ratchet_test.rb, which records it per app and stops it falling.
class ControllerCoverageContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read_app(app, relative)
    path = File.join(ROOT, app, relative)
    assert File.file?(path), "missing #{app}/#{relative}"
    File.read(path)
  end

  def assert_actions(body, *actions)
    actions.each do |action|
      assert_match(/\bdef\s+#{Regexp.escape(action)}\b/, body, "missing action ##{action}")
    end
  end

  def test_brgen_marketplace_orders_controller
    body = read_app("brgen", "app/controllers/marketplace/orders_controller.rb")
    assert_includes body, "class Marketplace::OrdersController"
    assert_actions body, "create", "update"
  end

  def test_brgen_marketplace_cart_send_offers
    body = read_app("brgen", "app/controllers/marketplace/carts_controller.rb")
    assert_includes body, "class Marketplace::CartsController"
    assert_actions body, "send_offers"
    routes = read_app("brgen", "config/routes.rb")
    assert_match(/send_offers|post\s+:send_offers/, routes)
  end

  def test_brgen_dating_swipe_controllers
    likes = read_app("brgen", "app/controllers/dating/likes_controller.rb")
    dislikes = read_app("brgen", "app/controllers/dating/dislikes_controller.rb")
    matches = read_app("brgen", "app/controllers/dating/matches_controller.rb")
    assert_includes likes, "class Dating::LikesController"
    assert_actions likes, "create"
    assert_includes dislikes, "class Dating::DislikesController"
    assert_actions dislikes, "create"
    assert_includes matches, "class Dating::MatchesController"
  end

  def test_brgen_takeaway_orders_controller
    body = read_app("brgen", "app/controllers/takeaway/orders_controller.rb")
    assert_includes body, "class Takeaway::OrdersController"
    assert_actions body, "create", "update"
  end

  def test_brgen_playlist_imports_controller
    body = read_app("brgen", "app/controllers/playlist/imports_controller.rb")
    assert_includes body, "class ImportsController"
    assert_actions body, "create"
  end

  def test_brgen_tv_broadcast_lifecycle
    live = read_app("brgen", "app/controllers/tv/live_streams_controller.rb")
    assert_match(/class\s+(?:Tv::)?LiveStreamsController/, live)
    assert_actions live, "create", "update", "go_live"
  end

  def test_brgen_sso_and_internal_status
    sso = read_app("brgen", "app/controllers/sso_controller.rb")
    internal = read_app("brgen", "app/controllers/internal_controller.rb")
    routes = read_app("brgen", "config/routes.rb")
    assert_includes sso, "Shared::SsoConsume"
    assert_includes internal, "def status"
    assert_match(/sso|from_master/, routes)
    assert_includes routes, "internal/status"
  end

  def test_amber_mutating_controllers
    outfits = read_app("amber", "app/controllers/outfits_controller.rb")
    items = read_app("amber", "app/controllers/items_controller.rb")
    assert_includes outfits, "class OutfitsController"
    assert_actions outfits, "create"
    assert_includes items, "class ItemsController"
    assert_actions items, "create", "update"
  end

  def test_amber_sso_and_internal
    sso = read_app("amber", "app/controllers/sso_controller.rb")
    internal = read_app("amber", "app/controllers/internal_controller.rb")
    assert_includes sso, "Shared::SsoConsume"
    assert_includes internal, "def status"
  end

  def test_bsdports_ports_and_sso
    ports = read_app("bsdports", "app/controllers/ports_controller.rb")
    sso = read_app("bsdports", "app/controllers/sso_controller.rb")
    internal = read_app("bsdports", "app/controllers/internal_controller.rb")
    assert_includes ports, "class PortsController"
    assert_includes sso, "Shared::SsoConsume"
    assert_includes internal, "def status"
  end
end
