# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/fake_config"

# data/models.yml's fallback_policy block was inert three ways at once: the key
# was written bare as `on:` so YAML 1.1 parsed it as the boolean true, nothing
# anywhere read `fallback_policy`, and the category names it listed were not
# categories this codebase produces. These tests pin all three.
class TestFailoverPolicy < Minitest::Test
  FakeConfig = Master::TestSupport::FakeConfig

  def models_yml
    Master.load_yaml(File.join(Master::ROOT, "data", "models.yml"))
  end

  def router
    Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new, root: Master::ROOT)
  end

  def test_the_policy_key_is_a_string_not_yaml_true
    policy = models_yml.fetch("fallback_policy")

    assert policy.key?("on"), "fallback_policy must be keyed by the string \"on\" — a bare on: parses as true"
    refute policy.key?(true), "fallback_policy still has a boolean key; quote it"
  end

  # Every entry has to be a category some Result.err actually carries, or the
  # comparison in failover_skip_model? silently matches nothing.
  def test_every_configured_category_is_one_the_code_produces
    produced = Dir.glob(File.join(Master::ROOT, "lib", "**", "*.rb")).flat_map do |path|
      File.read(path).scan(/category:\s*:([a-z_]+)/).flatten
    end.uniq

    models_yml.fetch("fallback_policy").fetch("on").each do |category|
      assert_includes produced, category, "fallback_policy.on lists #{category.inspect}, which no Result.err carries"
    end
  end

  def test_router_exposes_the_configured_categories
    assert_equal %i[timeout no_api_key rate_limit budget], router.failover_skip_categories
  end

  def test_retry_count_has_one_source
    refute models_yml.fetch("fallback_policy").key?("retries_per_tier"),
           "retry count belongs to failover.max_retries only"
    assert_equal 2, router.failover_max_retries
  end

  # The chain asks the router; without one it keeps the old hardcoded pair.
  class Chained
    include Master::Review::Agent::FallbackChain

    def initialize(model_router) = @model_router = model_router

    public :failover_skip_model?, :skip_categories
  end

  def test_chain_uses_the_router_policy
    chain = Chained.new(router)

    assert chain.failover_skip_model?(Master::Result.err("nope", category: :rate_limit))
    assert chain.failover_skip_model?(Master::Result.err("nope", category: :budget))
    refute chain.failover_skip_model?(Master::Result.err("nope", category: :provider_error))
  end

  def test_chain_falls_back_to_the_constant_without_a_router
    chain = Chained.new(nil)

    assert_equal Master::Review::Agent::FallbackChain::NON_RETRYABLE, chain.skip_categories
    assert chain.failover_skip_model?(Master::Result.err("nope", category: :timeout))
    refute chain.failover_skip_model?(Master::Result.err("nope", category: :rate_limit))
  end

  def test_ok_results_never_skip
    refute Chained.new(router).failover_skip_model?(Master::Result.ok("fine"))
  end
end
