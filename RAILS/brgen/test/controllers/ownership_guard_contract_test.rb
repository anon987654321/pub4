# frozen_string_literal: true

require "test_helper"

# Five separate controllers shipped `update`/`destroy` actions with no
# ownership check, independently, before this session's audit caught them
# (posts, delivery_drivers, tv/{channels,live_streams,videos},
# listening_parties). That's the same bug five times, not five unrelated
# bugs — this test turns "add an ownership check" from a convention someone
# has to remember into something CI actually verifies for every controller
# with a mutating action, present and future.
#
# A controller passes if it has ANY recognizable guard: a before_action
# naming an authorize/owner/host/admin method, an inline Pundit `authorize`
# call, an inline `Current.user == ...` / `...== Current.user` /
# `.owner?(Current.user)` check, or a finder that's already scoped to
# Current.user (e.g. `Current.user.posts.find(...)`) so no separate check
# is needed. Controllers with no ownership concept at all (session-only,
# token-authorized) are named explicitly below with a one-line reason —
# silence is not an allowlist entry.
class OwnershipGuardContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  # moderator counts: in this app a community's moderators are who may write its
  # queue, its bans and its wiki, and require_moderator! is that check spelled
  # the way the domain spells it. Without the word here, adding a moderated
  # surface reads as an unguarded one.
  GUARD_BEFORE_ACTION_RE = /before_action\s+(?:->\s*\{.*?\}|:?"?[a-z_!?]*(?:authorize|owner|admin|host|moderator)[a-z_!?]*"?)/i
  INLINE_AUTHORIZE_RE = /\bauthorize[\s(]/
  INLINE_EQUALITY_RE = /Current\.user\s*==|==\s*Current\.user|\.owner\?\(Current\.user\)/
  SELF_SCOPED_FINDER_RE = %r{
    Current\.user\.[a-z_]+\.(?:find|find_by!?|find_or_create_by!?|find_or_initialize_by!?|where|destroy_all|update_all) |
    \.(?:find_by|where)\([^)]*\b(?:user|follower|liker|disliker|initiator)_?i?d?:\s*Current\.user |
    \([^)]*Current\.user[^)]*\)\.find
  }x

  # Controller => one-line reason no per-record ownership check applies.
  NO_OWNERSHIP_CONCEPT = {
    "drafts_controller.rb" => "writes to session[:drafts] only — no AR record, nothing another user could touch",
    "email_subscriptions_controller.rb" => "token in the unsubscribe link is itself the authorization, not user login",
    "locations_controller.rb" => "only ever writes to Current.user's own row (me.update_columns); broadcasts are reads",
    "users_controller.rb" => "edit/update act on @user = Current.user only — never a param-supplied id",
  }.freeze

  def test_every_mutating_controller_has_an_ownership_guard
    unguarded = mutating_controllers.reject { |path| guarded?(path) || allowlisted?(path) }

    assert_empty unguarded,
      "controller(s) with update/destroy and no recognizable ownership guard:\n" \
      "#{unguarded.map { |p| "  - #{p.sub(ROOT + '/', '')}" }.join("\n")}\n" \
      "Add a before_action (authorize_owner!, require_X_owner!, ...), an inline " \
      "Current.user check, scope the finder to Current.user, or add a reasoned " \
      "entry to NO_OWNERSHIP_CONCEPT in this test if there's truly no per-record " \
      "ownership concept here."
  end

  # Proves the detector itself actually rejects the bug class it exists to
  # catch, using a fixture shaped exactly like the real bugs this session
  # found (before_action list with no owner check, direct .find + .destroy).
  def test_detector_rejects_a_controller_shaped_like_the_known_bug_class
    fixture = <<~RUBY
      class WidgetsController < ApplicationController
        before_action :require_real_user, only: %i[update destroy]
        before_action :set_widget, only: %i[update destroy]

        def update
          @widget.update(widget_params)
        end

        def destroy
          @widget.destroy
        end

        private

        def set_widget
          @widget = Widget.find(params[:id])
        end
      end
    RUBY

    refute guarded_source?(fixture), "detector should flag a controller with no owner check at all"
  end

  private

  def mutating_controllers
    Dir.glob(File.join(ROOT, "app", "controllers", "**", "*_controller.rb")).select do |path|
      source = File.read(path)
      source.match?(/\bdef\s+update\b/) || source.match?(/\bdef\s+destroy\b/)
    end.sort
  end

  def guarded?(path)
    guarded_source?(File.read(path))
  end

  def guarded_source?(source)
    source.match?(GUARD_BEFORE_ACTION_RE) ||
      source.match?(INLINE_AUTHORIZE_RE) ||
      source.match?(INLINE_EQUALITY_RE) ||
      source.match?(SELF_SCOPED_FINDER_RE)
  end

  def allowlisted?(path)
    NO_OWNERSHIP_CONCEPT.key?(File.basename(path))
  end
end
