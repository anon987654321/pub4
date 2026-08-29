# frozen_string_literal: true

require "minitest/autorun"

# TODO.md, brgen_allow_unauthenticated_access_is_a_noop: in an app
# whose User has a `guest` column, Shared::Authentication.allow_unauthenticated_access
# does nothing, and that is deliberate — guests get a soft Current.user so the
# product is usable without signup, and require_real_user is the identity gate.
#
# The part that was debt is that a control read as a control and returned in
# silence, so an author who wrote it got nothing and no warning. The fix is a
# dev/test log line. Nothing pinned it, which is how a fix of this shape is
# deleted by the next person tidying "unused" logging.
#
# Source-level on purpose: this is a class-method side effect at controller-class
# definition time, and RAILS/test/*.rb run under bare ruby with no app bundle.
class AuthNoopIsAudibleTest < Minitest::Test
  SOURCE = File.expand_path("../shared/app/controllers/concerns/shared/authentication.rb", __dir__)

  # TODO.md, Scanner Conventions 1: a rule and the paragraph explaining the rule
  # contain the same words. The comment above the guard says "silent no-op", so an
  # assertion over the raw file would pass on the explanation of the fix rather
  # than the fix.
  def code
    @code ||= File.readlines(SOURCE, encoding: "UTF-8")
                  .reject { |line| line.strip.start_with?("#") }
                  .join
  end

  def guest_branch
    body = code[/def allow_unauthenticated_access.*?\n      end\n/m]
    refute_nil body, "allow_unauthenticated_access is gone from #{SOURCE}"
    body
  end

  def test_the_guest_branch_still_returns_early
    assert_includes guest_branch, "return",
                    "if this stopped returning early, guests lost resume_session and the " \
                    "soft Current.user with it — that is a behaviour change, not a cleanup"
  end

  def test_the_no_op_announces_itself_before_returning
    branch = guest_branch
    warn_at = branch.index("Rails.logger")
    return_at = branch.index(/^\s+return$/)

    refute_nil warn_at,
               "the no-op is silent again. An author who writes " \
               "allow_unauthenticated_access in a guest-column app must be told it does " \
               "nothing, or it is inert config wearing the shape of a control."
    refute_nil return_at
    assert_operator warn_at, :<, return_at, "the warning must run before the early return"
  end

  # Production stays quiet: this would otherwise be boot noise on every controller
  # in the fleet.
  def test_the_warning_is_scoped_to_development_and_test
    branch = guest_branch

    assert_includes branch, "Rails.env.development?"
    assert_includes branch, "Rails.env.test?"
  end
end
