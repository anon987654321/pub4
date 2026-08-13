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

  # brgen's five verticals became mountable engines, so app/{models,controllers}/
  # <vertical>/ moved to engines/<vertical>/app/.... These contracts still asked
  # for the old path and had been red since; nothing in the gate suite runs this
  # file, so the failure was silent. Resolve either location.
  ENGINES = %w[dating marketplace playlist takeaway tv maps].freeze

  # The verticals' routes moved with them: engines/<vertical>/config/routes.rb.
  # These contracts assert that a route exists somewhere in the app's routing
  # surface, so reading routes.rb means reading the host's plus every engine's.
  def app_path(app, relative)
    direct = File.join(ROOT, app, relative)
    return direct if File.file?(direct)

    vertical = relative[%r{\Aapp/(?:models|controllers|views)/([a-z_]+)/}, 1]
    return direct unless ENGINES.include?(vertical)

    File.join(ROOT, app, "engines", vertical, relative)
  end

  def read_app(app, relative)
    return routing_surface(app) if relative == "config/routes.rb"

    path = app_path(app, relative)
    assert File.file?(path), "missing #{path.sub("#{ROOT}/", '')}"
    File.read(path)
  end

  def routing_surface(app)
    files = [File.join(ROOT, app, "config", "routes.rb")] +
            Dir.glob(File.join(ROOT, app, "engines", "*", "config", "routes.rb")).sort
    present = files.select { |f| File.file?(f) }
    assert present.any?, "missing #{app}/config/routes.rb"
    present.map { |f| File.read(f) }.join("\n")
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

  # The three apps are on two pagy majors -- amber 9.4, brgen 43.3, bsdports 43.5
  # -- and the view helpers were renamed across that boundary. `pagy_nav(@pagy)`
  # is pagy 9; pagy 43 has `@pagy.series_nav` and no pagy_nav at all. brgen's
  # hashtags/show.html.erb called pagy_nav while brgen ran 43, so that page
  # raised NoMethodError the moment a hashtag had a second page. Nothing caught
  # it, because the call is only reached when `pages > 1`.
  #
  # shared/_pager.html.erb now renders every pager off page/pages/next, which
  # both majors expose. `prev` is deliberately not among them -- pagy 43 renamed
  # it to `previous`, and that is exactly the kind of difference this guards.
  VERSION_SPECIFIC_PAGY_HELPERS = %w[pagy_nav pagy_info pagy_bootstrap_nav series_nav].freeze

  def test_views_do_not_call_a_pagy_helper_their_app_may_not_have
    views = Dir.glob(File.join(ROOT, "{amber,brgen,bsdports}", "app", "views", "**", "*.erb")) +
            Dir.glob(File.join(ROOT, "brgen", "engines", "*", "app", "views", "**", "*.erb")) +
            Dir.glob(File.join(ROOT, "shared", "app", "views", "**", "*.erb"))

    refute_empty views, "no views found — the glob stopped matching, which is blindness not cleanliness"

    offenders = views.flat_map do |path|
      in_comment = false
      File.readlines(path).each_with_index.filter_map do |line, i|
        # ERB comments span lines, and the earlier one-line version of this check
        # flagged the prose in _pager.html.erb that explains the rename.
        was_comment = in_comment
        in_comment = true if line.include?("<%#")
        skip = in_comment || was_comment
        in_comment = false if in_comment && line.include?("%>") && !line.rstrip.end_with?("<%#")
        next if skip

        helper = VERSION_SPECIFIC_PAGY_HELPERS.find { |h| line.include?(h) }
        next unless helper

        "#{path.delete_prefix("#{ROOT}/")}:#{i + 1} calls #{helper}"
      end
    end

    assert_empty offenders.sort,
                 "render shared/pager instead — these helpers exist in one pagy major and not the other"
  end

  # ENGINES.md and the marketplace README both said brgen main kept "the
  # craigslist/airbnb-style personal classifieds", with the engine as the
  # transactional storefront. There is no listing model in the host app --
  # app/models/marketplace.rb is a table-name-prefix module and nothing else --
  # so both docs sent a reader looking for a tier that was never built. Same
  # shape as the WIRING_NOTES dialect table that sent CSS work at the palette
  # brgen had left.
  #
  # This asserts the pair stays consistent in whichever direction it is resolved:
  # either the host has no listing model and the docs must not claim one, or
  # someone builds it and this test says to update the docs with it.
  def test_docs_do_not_claim_a_host_app_listing_model_that_does_not_exist
    host_models = Dir.glob(File.join(ROOT, "brgen", "app", "models", "*.rb")).map { |p| File.basename(p, ".rb") }
    host_has_listings = host_models.any? { |m| m =~ /\A(listing|classified|advert)/ }

    docs = {
      "brgen/ENGINES.md" => File.read(File.join(ROOT, "brgen", "ENGINES.md")),
      "brgen/engines/marketplace/README.md" =>
        File.read(File.join(ROOT, "brgen", "engines", "marketplace", "README.md")),
    }

    return if host_has_listings # the claim would be true; nothing to police

    claims = docs.filter_map do |name, body|
      # A claim is a sentence putting classifieds in the host app. The corrected
      # text names the absence explicitly, so exclude the lines that do that.
      offending = body.lines.each_with_index.select do |line, _|
        line =~ /classifieds/i && line =~ /host app|brgen main keeps/i && line !~ /used to say|does not|never/i
      end
      next if offending.empty?

      "#{name}:#{offending.first[1] + 1} — #{offending.first[0].strip[0, 70]}"
    end

    assert_empty claims,
                 "no listing model exists in brgen/app/models; these say the host app carries classifieds"
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
