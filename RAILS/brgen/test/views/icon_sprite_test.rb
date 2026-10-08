# frozen_string_literal: true

require "test_helper"

# The brgen homepage shipped 50KB of inline SVG for 22 distinct shapes, because
# the five feed-action icons were re-inlined for every one of 25 posts. They now
# reference a single sprite.
#
# Two things have to stay true for that to be a win rather than a bug: the paths
# must be emitted exactly once, and every <use> on the page must resolve to a
# <symbol> that is actually there — a dangling reference draws nothing at all and
# raises nothing, which is the failure shape this codebase keeps producing.
class IconSpriteTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def seed_feed(count)
    author = User.strict_loading(false).create!(
      email_address: "sprite-#{SecureRandom.hex(4)}@brgen.no", password: "password123", city: @city
    )
    community = Community.create!(name: "Sprite #{SecureRandom.hex(3)}", slug: "sprite-#{SecureRandom.hex(4)}")
    count.times { |i| Post.create!(user: author, community:, title: "Sprite #{i}", content: "…") }
  end

  def symbol_ids(body) = body.scan(/<symbol id="icon-([a-z_]+)"/).flatten
  def use_refs(body) = body.scan(/<use href="#icon-([a-z_]+)"/).flatten

  test "every use on the page resolves to a symbol that is present" do
    ActsAsTenant.with_tenant(@city) do
      seed_feed(6)
      get root_path
      assert_response :success

      defined_ids = symbol_ids(response.body)
      referenced = use_refs(response.body).uniq
      assert_operator referenced.size, :>, 0, "the page rendered no icons — this test proves nothing"
      assert_empty referenced - defined_ids,
                   "dangling <use> reference(s): these draw nothing and raise nothing"
    end
  end

  test "the sprite appears exactly once and holds every icon" do
    ActsAsTenant.with_tenant(@city) do
      get root_path
      ids = symbol_ids(response.body)
      assert_equal ids.size, ids.uniq.size, "the sprite was rendered more than once"
      assert_equal Shared::UiHelper::ICONS.sort, ids.sort,
                   "the sprite must carry the whole set — Turbo can inject markup referencing any icon"
    end
  end

  # The actual point of the change: icon bytes per post drop and stay dropped.
  # A post still costs something — it carries five feed-action icons, so the floor
  # is 5 outer <svg> wrappers however thin the contents are. Measured on a 23-post
  # feed: 1730B per post inlined, 624B through the sprite, and the whole document
  # 180,906B -> 150,552B. The threshold sits between the two, not below both.
  INLINED_BYTES_PER_POST = 1730
  SPRITE_BYTES_PER_POST = 624
  MAX_BYTES_PER_POST = 1000

  test "icon markup per post stays near the sprite cost, not the inlined cost" do
    ActsAsTenant.with_tenant(@city) do
      seed_feed(3)
      get root_path
      small = response.body.scan(%r{<svg.*?</svg>}m).join.bytesize

      seed_feed(20)
      get root_path
      large = response.body.scan(%r{<svg.*?</svg>}m).join.bytesize

      growth_per_post = (large - small) / 20.0
      assert_operator growth_per_post, :<, MAX_BYTES_PER_POST,
                      "SVG grew #{growth_per_post.round}B per post (sprite measured " \
                      "#{SPRITE_BYTES_PER_POST}B, inlining #{INLINED_BYTES_PER_POST}B) — icons are inlined again"
    end
  end

  # Paths belong in the sprite and nowhere else. Inlining is what this replaced.
  test "path data appears only inside the sprite" do
    ActsAsTenant.with_tenant(@city) do
      seed_feed(6)
      get root_path

      sprite = response.body[%r{<svg class="icon-sprite".*?</svg>}m]
      assert sprite, "the sprite did not render"
      outside = response.body.sub(sprite, "")
      icon_paths = outside.scan(/<path /).size

      # The marketplace animated logo and a handful of hand-built SVGs legitimately
      # carry their own paths; the feed-action icons must not be among them.
      assert_operator icon_paths, :<, 20,
                      "#{icon_paths} <path> elements outside the sprite suggests icons are inlined again"
    end
  end

  test "an unknown icon name raises instead of drawing nothing" do
    assert_raises(ArgumentError) { ApplicationController.helpers.icon(:definitely_not_an_icon) }
  end
end
