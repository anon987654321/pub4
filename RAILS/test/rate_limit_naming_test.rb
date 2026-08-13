# frozen_string_literal: true

require "minitest/autorun"

# Two rate limits on one controller are one rate limit unless they are named.
#
# ActionController::RateLimiting builds its counter key as
#
#     cache_key = ["rate-limit", scope, name, by].compact.join(":")
#
# with `scope` defaulting to controller_path and `name` to nil. So two
# `rate_limit` calls in one controller, both unnamed, address the same counter.
# Rails says so in the method's own docs — "If you want to use multiple rate
# limits per controller, you need to give each of them an explicit name via the
# `name:` option" — and four controllers here had not.
#
# It is not a subtle degradation. Each `rate_limit` registers its own
# before_action, so one request increments the shared counter once per limit,
# and `store.increment`'s expires_in only applies when the key is created. In
# MessagesController that meant: 30/minute and 40/3-minutes on :create, sharing
# a key for every signed-out sender, the counter going up by two per message,
# the 30 filter blocking after 15, and the 3-minute window never existing —
# whichever call created the key set a 1-minute TTL for both.
#
# The declaration looked exactly like a working two-tier limit. This is the
# repo's own dominant defect class (inert config, a reader that is not there),
# and it needed no code change to introduce: two correct-looking lines.
class RateLimitNamingTest < Minitest::Test
  RAILS_ROOT = File.expand_path("..", __dir__)

  def controllers
    @controllers ||= Dir[
      File.join(RAILS_ROOT, "{brgen,amber,bsdports}/app/controllers/**/*.rb"),
      File.join(RAILS_ROOT, "brgen/engines/*/app/controllers/**/*.rb"),
      File.join(RAILS_ROOT, "shared/app/controllers/**/*.rb")
    ].sort
  end

  # A rate_limit call and its continuation line, which is where `with:` usually
  # sits in this codebase.
  def rate_limit_calls(src)
    src.scan(/^[ \t]*rate_limit\b[^\n]*(?:\n[ \t]+[^\n]*)*/)
  end

  def unnamed_pairs
    controllers.filter_map do |path|
      calls = rate_limit_calls(File.read(path))
      next if calls.size < 2

      # scope: overrides the controller_path half of the key, so it separates
      # two limits just as well as name: does.
      unnamed = calls.reject { |c| c.match?(/\b(name|scope):/) }
      next if unnamed.empty?

      "#{path.sub("#{RAILS_ROOT}/", '')} (#{calls.size} limits, #{unnamed.size} unnamed)"
    end
  end

  def test_every_controller_with_two_rate_limits_names_them
    assert_empty unnamed_pairs,
                 "these controllers declare more than one rate_limit without `name:`, so the limits " \
                 "share one counter and the tightest of them answers for all — give each a name: or a scope:"
  end

  # The rule above is only worth enforcing while Rails still composes the key
  # that way. If a future Rails separates limits by declaration order, this test
  # is enforcing a rule about nothing, and it should say so rather than go on
  # passing — the same failure as an exemption outliving its subject.
  def test_the_rails_behaviour_this_rule_depends_on_is_still_true
    source = rate_limiting_source
    skip "actionpack rate_limiting.rb not found on this host — rule unverified, not disproved" unless source

    assert_match(/cache_key\s*=\s*\[\s*"rate-limit"/, source,
                 "ActionController::RateLimiting no longer builds a cache_key the way this rule assumes")
    assert_match(/\bname\b/, source[/cache_key\s*=.*$/].to_s,
                 "the rate-limit cache key no longer includes `name:`, so naming may no longer separate " \
                 "two limits — re-derive this rule against the installed Rails before trusting it")
  end

  # Located by walking the loaded gem paths rather than by booting Rails: every
  # file in this directory runs under bare `ruby` with no app bundle.
  def rate_limiting_source
    candidates = Gem.path.flat_map do |root|
      Dir[File.join(root, "gems", "actionpack-*", "lib", "action_controller", "metal", "rate_limiting.rb")]
    end
    path = candidates.max_by { |f| Gem::Version.new(f[/actionpack-([\d.]+)/, 1]) }
    path && File.read(path)
  end
end
