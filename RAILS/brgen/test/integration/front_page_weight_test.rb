# frozen_string_literal: true

require "test_helper"

# P0.4's payload item, as a budget rather than a number in a document.
#
# The front page is brgen's primary surface and it is read on a 390px phone. The
# backlog recorded 271 Stimulus controller instances and 229,773 bytes of HTML,
# re-measured by hand twice, and both numbers moved between measurements without
# anything noticing — which is the same failure the method and file ratchets
# exist to stop. Per-post cost is what scales: chrome is paid once, everything in
# _post.html.erb is paid 25 times.
#
# The two reductions this pins:
#
#   popover, 4 per post (100 instances). Each held a tooltip repeating the text
#   already in the button's own aria-label, and hover does not exist on the
#   viewport this page is designed for, so all 100 were unreachable there.
#
#   action on the repost button, 1 per post (25 instances). There is no repost
#   feature anywhere in the tree — no route, model, controller or column — and
#   action_controller#toggle guards its fetch on `if (this.urlValue)`, which that
#   button did not set. Clicking it added the active class, sent nothing, and
#   told the reader their repost had landed.
#
# The budget is deliberately close to the current number. Slack is room for the
# next 100-instance mistake to land without failing anything.
class FrontPageWeightTest < ActionDispatch::IntegrationTest
  POSTS = 25

  # Measured 2026-08-10 against a seeded feed of POSTS posts: 144 instances,
  # 140,236 bytes. Lower these when you cut something; raising one needs a reason
  # in the commit.
  INSTANCE_BUDGET = 150
  PER_POST_BUDGET = 5 # action x2, clipboard x2, dropdown x1

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def seed_feed
    ActsAsTenant.with_tenant(@city) do
      author = User.strict_loading(false).create!(
        email_address: "weight-#{SecureRandom.hex(4)}@brgen.no",
        password: "password123", city: @city,
      )
      community = Community.create!(name: "Weight #{SecureRandom.hex(3)}",
                                    slug: "weight-#{SecureRandom.hex(4)}")
      POSTS.times do |i|
        Post.create!(user: author, community: community,
                     title: "Weight post #{i}", content: "Body #{i}. " * 3)
      end
    end
  end

  def controller_instances(body)
    body.scan(/data-controller="([^"]*)"/).flatten
        .flat_map { |value| value.split(/\s+/).reject(&:empty?) }
  end

  # ERB comments removed before any source check. The first run of this file
  # counted three `action` controllers in a partial that renders two, and passed
  # the popover check only because it failed — both times it was reading the
  # comment that explains why those things are gone. A source scan that matches
  # its own rationale measures the documentation, not the code.
  def post_partial
    File.read(Rails.root.join("app/views/posts/_post.html.erb")).gsub(/<%#.*?%>/m, "")
  end

  test "the front page stays inside its Stimulus instance budget" do
    seed_feed
    get root_path
    assert_response :success

    instances = controller_instances(response.body)
    assert_operator instances.size, :<=, INSTANCE_BUDGET,
                    "front page boots #{instances.size} controller instances, budget is " \
                    "#{INSTANCE_BUDGET}. Counts: #{instances.tally.sort_by { |_, n| -n }.first(6).inspect}"
  end

  test "the post partial pays for at most PER_POST_BUDGET controllers per post" do
    per_post = post_partial.scan(/data-controller="([^"]*)"/).flatten
                      .flat_map { |value| value.split(/\s+/).reject(&:empty?) }

    assert_operator per_post.size, :<=, PER_POST_BUDGET,
                    "each post carries #{per_post.size} controllers (#{per_post.tally.inspect}); " \
                    "on a #{POSTS}-post feed that is #{per_post.size * POSTS} instances"
  end

  # This test used to assert the opposite: that no repost backend existed and
  # the button stayed inert, because for months a press toggled a class and
  # discarded the click. The backend exists now, so the contract inverts —
  # the button must reach it, and must not go back to being decorative.
  test "the repost button reaches a real endpoint" do
    assert Post.new.respond_to?(:reposted_by?), "Post lost its repost predicate"
    assert defined?(Repost), "the Repost model is gone but the button remains"

    assert_match(/post_repost_path/, post_partial,
                 "the repost button must post to the repost endpoint, not sit inert")

    # button_to, not data-controller="action": the action controller's optimistic
    # toggle is what let a failed request look like a success, and a third
    # Stimulus instance per card breaks PER_POST_BUDGET.
    repost_markup = post_partial[/button_to post_repost_path.*?<% end %>/m].to_s
    refute_empty repost_markup, "the repost button has moved; re-point this test"
    refute_match(/data-controller="[^"]*action/, repost_markup,
                 "action#toggle would restore the optimistic-success bug this replaced")
  end

  test "hover-only popovers stay out of the feed" do
    refute_match(/popover/, post_partial,
                 "popover duplicated each button's aria-label and cannot fire on touch — " \
                 "it cost 100 of the page's 271 instances")
  end
end
