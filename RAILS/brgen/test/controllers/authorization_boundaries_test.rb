# frozen_string_literal: true

require "test_helper"

# Two untested authorization boundaries, picked by blast radius rather than by
# how easy they were to test.
#
# brgen has 17 controller tests against 94 controllers, and 52 of the untested
# ones mutate state. These two are where an untested mistake costs most: the
# moderation panel decides who can act on reports, and blocks decide whose
# content a user has to see. Neither had a single test.
#
# The properties asserted here are the ones a refactor breaks silently — a
# redirect that stops happening, or a scope quietly widened from "my blocks" to
# "any block". A feature test would not catch either.
class AuthorizationBoundariesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def user(prefix, email: nil)
    User.strict_loading(false).create!(
      email_address: email || "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", city: @city,
    )
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def admin_email = ENV.fetch("BRGEN_ADMIN_EMAIL", "admin@brgen.no")

  # --- moderation panel -----------------------------------------------------

  test "the moderation queue turns away a signed-in non-admin" do
    ActsAsTenant.with_tenant(@city) do
      sign_in(user("ordinary"))
      get admin_reports_path

      assert_redirected_to root_path
    end
  end

  test "the moderation queue turns away a signed-out visitor" do
    ActsAsTenant.with_tenant(@city) do
      get admin_reports_path

      # Soft guests get a Current.user on this app, so the admin check is the
      # only thing standing between an anonymous visitor and the queue.
      assert_response :redirect
      refute_equal admin_reports_path, response.location&.sub(%r{\Ahttps?://[^/]+}, "")
    end
  end

  test "the admin reaches the queue and its counts come from the database" do
    ActsAsTenant.with_tenant(@city) do
      admin = user("admin", email: admin_email)
      reporter = user("reporter")
      author = user("reported")
      community = Community.create!(name: "Mod #{SecureRandom.hex(3)}", slug: "mod-#{SecureRandom.hex(4)}")
      post = Post.create!(user: author, community:, title: "Reported", content: "…")

      %w[open open reviewing resolved].each do |status|
        ModerationReport.create!(user: reporter, reportable: post, reason: "spam", status:)
      end

      # require_admin! reads BRGEN_ADMIN_EMAIL and denies when it is unset —
      # there is deliberately no default, since a default would be an account
      # that grants itself the queue. The test has to supply what production
      # supplies, rather than assume a fallback the controller does not have.
      previous = ENV["BRGEN_ADMIN_EMAIL"]
      ENV["BRGEN_ADMIN_EMAIL"] = admin_email
      admin.update!(email_verified_at: Time.current) if admin.respond_to?(:email_verified_at)

      sign_in(admin)
      get admin_reports_path

      assert_response :success
      # 2 open and 1 reviewing, counted by a grouped COUNT rather than by loading
      # the table twice and counting in Ruby (e4e1e1fe4). The numbers are what
      # the moderator triages by, so they are worth asserting rather than the
      # query shape.
      assert_select "body", /2/
      assert_includes response.body, "1"
    ensure
      ENV["BRGEN_ADMIN_EMAIL"] = previous
    end
  end

  # The identicon is drawn from the numeric id alone, never from account state
  # (0dd0fc2be): a 404 for a departing account would itself reveal the
  # departure, so its answer must look exactly like any other id's.
  test "a departing user's avatar is indistinguishable from any other id" do
    target = user("avatar-target")
    target.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    get avatar_user_path(target)
    departed = [ response.status, response.media_type, response.headers["Cache-Control"] ]

    get avatar_user_path(User.maximum(:id).to_i + 1000)

    assert_equal [ response.status, response.media_type, response.headers["Cache-Control"] ], departed
    assert_response :ok
  end

  # --- blocks ---------------------------------------------------------------

  test "blocking a user records it" do
    ActsAsTenant.with_tenant(@city) do
      blocker = user("blocker")
      target = user("target")
      sign_in(blocker)

      assert_difference "Block.count", +1 do
        post block_user_path(user_id: target.id)
      end
      assert_includes blocker.reload.blocked_users, target
    end
  end

  # The one that matters. blocks#destroy looks the block up through
  # Current.user.blocks_as_blocker, so a third party cannot lift it. Widening
  # that to Block.find_by would be an invisible change in review and would let
  # anyone unblock themselves from anyone.
  test "a third party cannot lift a block someone else placed" do
    ActsAsTenant.with_tenant(@city) do
      blocker = user("owner")
      target = user("blocked")
      meddler = user("meddler")
      blocker.block!(target)

      sign_in(meddler)

      assert_no_difference "Block.count" do
        delete unblock_user_path(user_id: target.id)
      end
      assert_includes blocker.reload.blocked_users, target,
                      "a block must only be liftable by the user who placed it"
    end
  end

  test "the user who placed a block can lift it" do
    ActsAsTenant.with_tenant(@city) do
      blocker = user("lifter")
      target = user("lifted")
      blocker.block!(target)

      sign_in(blocker)

      assert_difference "Block.count", -1 do
        delete unblock_user_path(user_id: target.id)
      end
      refute_includes blocker.reload.blocked_users, target
    end
  end

  # Messenger: group settings and message edits.

  test "a group member who is not an admin cannot change the disappearing timer" do
    ActsAsTenant.current_tenant = @city
    founder = user("timer-founder")
    member = user("timer-member")
    group = Conversation.create_group!(creator: founder, name: "Timer", users: [ member ])
    sign_in(member)

    patch conversation_path(group), params: { disappearing: "1h" }

    assert_redirected_to conversation_path(group)
    assert_nil group.reload.disappearing_duration
    assert_equal I18n.t("flash.settings_update_failed"), flash[:alert]
  end

  # An inline onchange handler stops running once the CSP leaves report-only.
  test "the disappearing timer submits through Stimulus with a no-script Save" do
    ActsAsTenant.current_tenant = @city
    founder = user("timer-own")
    group = Conversation.create_group!(creator: founder, name: "Timer", users: [ user("timer-peer") ])
    sign_in(founder)

    get conversation_path(group)

    assert_response :success
    assert_select "form[data-controller='auto-submit'] select#disappearing[data-action='change->auto-submit#submit']"
    assert_select "select#disappearing[onchange]", count: 0
    assert_select "form[data-controller='auto-submit'] noscript", 1
  end

  test "a blank message edit answers 422 and keeps the text" do
    ActsAsTenant.current_tenant = @city
    me = user("edit-me")
    other = user("edit-other")
    conversation = Conversation.find_or_create_direct(me, other)
    message = conversation.messages.create!(sender: me, content: "hei", message_type: "text")
    sign_in(me)

    patch conversation_message_path(conversation, message), params: { message: { content: "" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal "hei", message.reload.content
  end
end
