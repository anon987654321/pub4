# frozen_string_literal: true

require "minitest/autorun"

# A write a guest can reach, with nothing limiting how often.
#
# Found by asking the narrow version of a question the 2026-08-10 audit asked
# too broadly. That audit counted "64 controllers with a create and no
# rate_limit" and the entry in OPENBSD/data/debt.yml says so itself: "the subset
# worth doing is the write endpoints a guest can reach, not all 64 at an
# arbitrary threshold." Most of the 64 are behind authentication, where the
# account is the limit. Fourteen were guest-adjacent; three were genuinely
# guest-reachable writes with no limit at all, and each one had a real cost:
#
#   Fediverse::InboxesController#create   an outbound HTTPS GET to a URL from
#                                         the sender's own Signature header,
#                                         before the signature is verified
#   EmailSubscriptionsController#create   queues mail to an arbitrary address,
#                                         over brgen.no's SPF and DKIM
#   amber RegistrationsController#create  unlimited accounts, while brgen's
#                                         equivalent had carried 10/10min all along
#
# This is the gate rather than only the fix, because the fix is three lines that
# a refactor removes without noticing. It reads source text and never boots
# Rails, like every other file in this directory.
class GuestWriteRateLimitTest < Minitest::Test
  RAILS_ROOT = File.expand_path("..", __dir__)

  WRITE_ACTIONS = %w[create update destroy].freeze

  # brgen gates guests with a `require_real_user` before_action rather than with
  # Rails' own allow_unauthenticated_access, so skipping it is the second way an
  # action becomes guest-reachable. Missing this is how a checker reports zero.
  GUEST_GATES = [
    /allow_unauthenticated_access(?!\s*,?\s*only)/,
    /skip_before_action\s+:require_real_user/,
  ].freeze

  def controllers
    @controllers ||= Dir[
      File.join(RAILS_ROOT, "{brgen,amber,bsdports}/app/controllers/**/*.rb"),
      File.join(RAILS_ROOT, "brgen/engines/*/app/controllers/**/*.rb"),
      File.join(RAILS_ROOT, "shared/app/controllers/**/*.rb")
    ].sort
  end

  # The action names in an `only:` / `except:` list, in either literal form.
  def action_list(fragment)
    return nil if fragment.nil?

    fragment.scan(/:(\w+)/).flatten | fragment.scan(/%i\[([^\]]*)\]/).flatten.flat_map(&:split)
  end

  # Which write actions in this file a request with no session can reach.
  def guest_writes(src)
    defined_writes = WRITE_ACTIONS.select { |a| src.match?(/^\s*def #{a}\b/) }
    return [] if defined_writes.empty?

    return defined_writes if GUEST_GATES.any? { |re| src.match?(re) }

    scoped = src[/allow_unauthenticated_access\s+only:\s*(%i\[[^\]]*\]|\[[^\]]*\])/, 1]
    defined_writes & (action_list(scoped) || [])
  end

  # Which actions a rate_limit in this file covers. A rate_limit with no `only:`
  # covers every action, which is why the nil case is "all" and not "none".
  def rate_limited(src)
    src.scan(/rate_limit\b[^\n]*(?:\n\s+[^\n]*)?/).flat_map do |call|
      scoped = call[/only:\s*(%i\[[^\]]*\]|\[[^\]]*\]|:\w+)/, 1]
      scoped ? action_list(scoped) : WRITE_ACTIONS
    end
  end

  def gaps
    controllers.flat_map do |path|
      src = File.read(path)
      covered = rate_limited(src)
      (guest_writes(src) - covered).map { |action| "#{path.sub("#{RAILS_ROOT}/", '')}##{action}" }
    end.sort
  end

  def test_no_guest_reachable_write_action_is_unlimited
    assert_empty gaps,
                 "these write actions are reachable without a session and nothing limits their rate — " \
                 "add `rate_limit to:, within:, only:` to each, or authenticate the action"
  end

  # The instrument, not the tree. A source-text checker that stops matching
  # reports zero gaps and reads exactly like a clean tree — which is the failure
  # this repo has already had (RAILS gates stopped seeing 57 views when the
  # verticals moved to engines, and the falling count read as improvement).
  #
  # So: prove the detector still finds guest writes at all, and prove it still
  # finds them where they are known to be. Both numbers are floors, not equality
  # assertions — this file must not need editing every time a controller is added.
  def test_the_detector_still_finds_guest_reachable_writes
    found = controllers.sum { |path| guest_writes(File.read(path)).size }

    assert_operator found, :>=, 5,
                    "only #{found} guest-reachable write action(s) found across #{controllers.size} " \
                    "controllers — the detector has stopped matching, and an empty gaps list means nothing"
  end

  def test_the_detector_still_reads_the_limits_that_close_the_gaps
    {
      "brgen/app/controllers/fediverse/inboxes_controller.rb" => "create",
      "brgen/app/controllers/email_subscriptions_controller.rb" => "create",
      "amber/app/controllers/registrations_controller.rb" => "create",
    }.each do |file, action|
      src = File.read(File.join(RAILS_ROOT, file))

      assert_includes guest_writes(src), action, "#{file}: #{action} should read as guest-reachable"
      assert_includes rate_limited(src), action, "#{file}: the rate_limit on #{action} is no longer parsed"
    end
  end
end
