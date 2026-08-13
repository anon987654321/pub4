# frozen_string_literal: true

require "minitest/autorun"

# Same caveat as controller_coverage_contract_test.rb: this asserts that source files
# contain the classes and methods apps.yml claims, not that anything is tested. The
# per-app tested/untested count is in coverage_ratchet_test.rb.
class ModelCoverageContractTest < Minitest::Test
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

  # Vertical tests moved into engines/<vertical>/test/ with everything else.
  def assert_app_file(app, relative)
    assert File.file?(app_path(app, relative)) ||
           File.file?(File.join(ROOT, app, "engines", relative[%r{\Atest/\w+/([a-z_]+)/}, 1].to_s, relative)),
           "missing #{app}/#{relative}"
  end

  def routing_surface(app)
    files = [File.join(ROOT, app, "config", "routes.rb")] +
            Dir.glob(File.join(ROOT, app, "engines", "*", "config", "routes.rb")).sort
    present = files.select { |f| File.file?(f) }
    assert present.any?, "missing #{app}/config/routes.rb"
    present.map { |f| File.read(f) }.join("\n")
  end

  def test_brgen_dating_match_model_is_wired
    match = read_app("brgen", "app/models/dating/match.rb")
    controller = read_app("brgen", "app/controllers/dating/matches_controller.rb")
    routes = read_app("brgen", "config/routes.rb")
    apps_yml = File.read(File.join(ROOT, "apps.yml"))

    assert_includes match, "class Dating::Match < ApplicationRecord"
    assert_includes match, "belongs_to :initiator"
    assert_includes match, "belongs_to :receiver"
    assert_includes match, "validates :initiator_id, uniqueness:"
    assert_includes match, "validates :status, inclusion:"
    assert_includes match, "scope :active"
    assert_includes match, "def other_user"
    assert_includes match, "announce_match"
    assert_includes controller, "Dating::Match.active"
    assert_includes routes, "resources :matches"
    assert_includes apps_yml, "Dating::Match"
    assert_app_file("brgen", "test/models/dating/match_test.rb")
  end

  def test_brgen_marketplace_order_model_is_wired
    order = read_app("brgen", "app/models/marketplace/order.rb")
    controller = read_app("brgen", "app/controllers/marketplace/orders_controller.rb")
    routes = read_app("brgen", "config/routes.rb")

    assert_includes order, "class Marketplace::Order < ApplicationRecord"
    assert_includes order, "belongs_to :buyer"
    assert_includes order, "belongs_to :listing"
    assert_includes order, "STATUSES ="
    assert_includes order, "validates :status, inclusion:"
    assert_includes order, "def accept!"
    assert_includes order, "def decline!"
    assert_includes controller, "Marketplace::OrdersController"
    assert_includes routes, "resources :orders"
    assert_app_file("brgen", "test/models/marketplace/order_test.rb")
  end

  def test_brgen_takeaway_order_model_is_wired
    order = read_app("brgen", "app/models/takeaway/order.rb")
    controller = read_app("brgen", "app/controllers/takeaway/orders_controller.rb")
    routes = read_app("brgen", "config/routes.rb")

    assert_includes order, "class Takeaway::Order < ApplicationRecord"
    assert_includes order, "belongs_to :user"
    assert_includes order, "belongs_to :restaurant"
    assert_includes order, "has_many :order_items"
    assert_includes order, "TRANSITIONS ="
    assert_includes order, "validates :status, inclusion:"
    assert_includes order, "validates :delivery_address, presence: true"
    assert_includes order, "def transition_to!"
    assert_includes controller, "Takeaway::OrdersController"
    assert_includes routes, "resources :orders"
    assert_app_file("brgen", "test/models/takeaway/order_test.rb")
  end

  def test_brgen_vote_model_and_votable_concern_are_wired
    vote = read_app("brgen", "app/models/vote.rb")
    votable = File.read(File.join(ROOT, "shared/app/models/concerns/shared/votable.rb"))
    post = read_app("brgen", "app/models/post.rb")
    controller = read_app("brgen", "app/controllers/votes_controller.rb")
    routes = read_app("brgen", "config/routes.rb")

    assert_includes vote, "class Vote < ApplicationRecord"
    assert_includes vote, "belongs_to :user"
    assert_includes vote, "belongs_to :votable, polymorphic: true"
    assert_includes vote, "validates :value, inclusion:"
    assert_includes vote, "validates :user_id, uniqueness:"
    assert_includes votable, "module Votable"
    assert_includes votable, "has_many :votes, as: :votable"
    assert_includes post, "include Shared::Votable"
    assert_includes controller, "find_votable"
    assert_includes routes, 'controller: "votes"'
    assert_app_file("brgen", "test/models/vote_test.rb")
  end

  def test_amber_outfit_model_is_wired
    outfit = read_app("amber", "app/models/outfit.rb")
    controller = read_app("amber", "app/controllers/outfits_controller.rb")
    routes = read_app("amber", "config/routes.rb")

    assert_includes outfit, "class Outfit < ApplicationRecord"
    assert_includes outfit, "belongs_to :user"
    assert_includes outfit, "has_many :outfit_items"
    assert_includes outfit, "has_many :items, through: :outfit_items"
    assert_includes outfit, "validates :name, presence: true"
    assert_includes outfit, "def context_label"
    assert_includes controller, "OutfitGeneration"
    assert_includes routes, "resources :outfits"
    assert_app_file("amber", "test/models/outfit_test.rb")
  end

  def test_amber_wardrobe_item_model_is_wired
    wardrobe_item = read_app("amber", "app/models/wardrobe_item.rb")
    controller = read_app("amber", "app/controllers/wardrobe_items_controller.rb")
    routes = read_app("amber", "config/routes.rb")

    assert_includes wardrobe_item, "class WardrobeItem < ApplicationRecord"
    assert_includes wardrobe_item, "belongs_to :user"
    assert_includes wardrobe_item, "belongs_to :item"
    assert_includes wardrobe_item, "CONDITIONS ="
    assert_includes wardrobe_item, "validates :condition, inclusion:"
    assert_includes wardrobe_item, "validates :user_id, uniqueness:"
    assert_includes controller, "WardrobeAnalytics"
    assert_includes routes, "resources :wardrobe_items"
    assert_app_file("amber", "test/models/wardrobe_item_test.rb")
  end

  def test_amber_connection_model_is_wired
    connection = read_app("amber", "app/models/connection.rb")
    controller = read_app("amber", "app/controllers/connections_controller.rb")
    routes = read_app("amber", "config/routes.rb")

    assert_includes connection, "class Connection < ApplicationRecord"
    assert_includes connection, "STATUSES = %w[pending accepted blocked]"
    assert_includes connection, "belongs_to :requester"
    assert_includes connection, "belongs_to :addressee"
    assert_includes connection, "validates :status, inclusion:"
    assert_includes connection, "validate :no_self_connection"
    assert_includes connection, "def accept!"
    assert_includes controller, "ConnectionsController"
    assert_includes routes, "resources :connections"
    assert_app_file("amber", "test/models/connection_test.rb")
  end
end
