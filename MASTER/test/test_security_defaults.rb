# frozen_string_literal: true

require_relative "test_helper"

# data/security/defaults.yml described a local-first, zero-listener, explicitly
# paired, fail-closed system. Exactly one of its keys had a reader. The rest — the
# gateway bind, the dashboard, the session trust tiers, the pairing TTL, the
# ingress rate limit, the five tool deny patterns — read as enforced policy and
# enforced nothing, and the ingress limit was additionally hardcoded in the
# controller so the file and the code could drift apart silently.
#
# The file now separates enforced keys from recorded intent. This test is what
# keeps that split true, in both directions: an enforced key that loses its reader
# fails, and a planned key that grows one fails until it moves up. The readers are
# named explicitly rather than grepped for the leaf name, because leaf names here
# are words like "enabled", "port" and "trust" — a name grep would find those
# anywhere and call the file enforced.
class TestSecurityDefaults < Minitest::Test
  PATH = Master.data_path("security/defaults.yml")

  # enforced path => [file that reads it, the expression it reads it with]
  READERS = {
    %w[ingress rate_limit_per_minute] => ["web/app/controllers/ingress_controller.rb", "rate_limit_per_minute"],
    %w[ingress window_seconds] => ["web/app/controllers/ingress_controller.rb", "window_seconds"],
    %w[tools custom require_review_for_destructive] =>
      ["lib/cli/destructive_routes.rb", "require_review_for_destructive"],
    %w[tools profiles public] => ["lib/ground/tool_profile.rb", "profiles"],
    %w[tools profiles messaging] => ["lib/ground/tool_profile.rb", "profiles"],
    %w[pairing required_for_remote_channels] => ["lib/ground/pairing.rb", "required_for_remote_channels"],
    %w[pairing code_ttl_seconds] => ["lib/ground/pairing.rb", "code_ttl_seconds"],
    %w[pairing allowlist_path] => ["lib/ground/pairing.rb", "allowlist_path"],
    %w[pairing redeem_per_minute] => ["lib/ground/pairing.rb", "redeem_per_minute"],
    %w[pairing redeem_window_seconds] => ["lib/ground/pairing.rb", "redeem_window_seconds"],
  }.freeze

  def defaults
    @defaults ||= Master.load_yaml(PATH)
  end

  def leaf_paths(node, prefix = [])
    return [prefix] unless node.is_a?(Hash)

    node.flat_map { |key, value| leaf_paths(value, prefix + [key.to_s]) }
  end

  def source(relative)
    File.read(File.join(Master::ROOT, relative))
  end

  def test_every_enforced_key_is_read_by_the_file_that_claims_to_read_it
    READERS.each do |path, (relative, expression)|
      refute_nil defaults.dig(*path), "#{path.join(".")} is gone from #{PATH}"
      assert_includes source(relative), expression,
                      "#{relative} no longer reads #{path.join(".")} — move the key under planned: or fix the reader"
    end
  end

  def test_the_enforced_half_is_exactly_the_documented_readers
    enforced = leaf_paths(defaults).reject { |path| path.first == "planned" }

    assert_equal READERS.keys.sort, enforced.sort,
                 "a top-level key changed. Every enforced key needs an entry in READERS; " \
                 "anything without a reader belongs under planned:"
  end

  # The other direction, and the one that matters: this is how the file filled up
  # with policy nothing applied.
  def test_nothing_under_planned_has_grown_a_reader
    planned = Array(defaults["planned"])
    refute_empty planned, "planned: should hold the recorded-but-unimplemented policy"

    # Distinctive leaf names only — "enabled" or "port" would match half the tree.
    distinctive = %w[deny_patterns require_scope channel_default health_path]
    sources = Dir.glob(File.join(Master::ROOT, "{lib,core,bin,web/app}", "**", "*.rb"))

    distinctive.each do |name|
      readers = sources.select { |path| File.read(path).include?(name) }
      assert_empty readers.map { |path| path.sub("#{Master::ROOT}/", "") },
                   "#{name} is under planned: but now has a reader — promote it out of planned:"
    end
  end

  def test_ingress_controller_uses_the_file_rather_than_its_own_constant
    body = source("web/app/controllers/ingress_controller.rb")

    refute_includes body, "INGRESS_RATE_LIMIT = 30",
                    "the hardcoded limit is back; the file is the source"
    assert_includes body, "DEFAULT_RATE_LIMIT", "keep a fallback for a checkout without the yaml"
  end
end
