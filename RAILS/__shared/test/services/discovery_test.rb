# frozen_string_literal: true

require "minitest/autorun"
require "time"

module Shared; end
def Time.current = Time.now

require_relative "../../app/services/shared/discovery/context"
require_relative "../../app/services/shared/discovery/candidate"
require_relative "../../app/services/shared/discovery/registry"
require_relative "../../app/services/shared/discovery/engine"

# Bare Minitest, no Rails: the point of the Context boundary is that a
# provider can be exercised without a request, and a test that needed the app
# bundle would not prove that.
class SharedDiscoveryTest < Minitest::Test
  D = Shared::Discovery

  def setup = D::Registry.clear!
  def teardown = D::Registry.clear!

  def context(**args) = D::Context.new(vertical: "brgen", **args)

  def candidate(score:, reason_key: "discovery.reason.nearby")
    D::Candidate.new(record: Object.new, reason_key:, score:)
  end

  def test_providers_accumulate_rather_than_replace
    first = ->(_ctx) { [candidate(score: 1.0)] }
    second = ->(_ctx) { [candidate(score: 2.0)] }
    D::Registry.register(:brgen, first)
    D::Registry.register(:brgen, second)

    assert_equal 2, D::Registry.providers_for(:brgen).length
  end

  def test_registering_the_same_provider_twice_does_not_duplicate_it
    provider = ->(_ctx) { [] }
    D::Registry.register(:brgen, provider)
    D::Registry.register(:brgen, provider)

    assert_equal 1, D::Registry.providers_for(:brgen).length
  end

  def test_general_providers_reach_every_app
    D::Registry.register(:general, ->(_ctx) { [] })
    assert_equal 1, D::Registry.providers_for(:amber).length
  end

  def test_registry_refuses_something_that_cannot_be_called
    assert_raises(ArgumentError) { D::Registry.register(:brgen, "not a provider") }
  end

  def test_engine_ranks_by_score_and_honours_the_limit
    D::Registry.register(:brgen, ->(_ctx) { [candidate(score: 1.0), candidate(score: 9.0), candidate(score: 5.0)] })
    results = D::Engine.new(context: context, limit: 2).call

    assert_equal 2, results.length
    assert_equal [9.0, 5.0], results.map(&:score)
  end

  # One provider raising must not empty the rail.
  def test_a_failing_provider_does_not_take_the_others_with_it
    D::Registry.register(:brgen, ->(_ctx) { raise "boom" })
    D::Registry.register(:brgen, ->(_ctx) { [candidate(score: 3.0)] })
    engine = D::Engine.new(context: context)

    assert_equal 1, engine.call.length
  end

  # ...and must not do it quietly. An empty rail and a broken rail look the
  # same on the page, which is how wiring in this tree goes dead unnoticed.
  def test_a_failing_provider_is_recorded
    D::Registry.register(:brgen, ->(_ctx) { raise "boom" })
    engine = D::Engine.new(context: context)
    engine.call

    assert_equal 1, engine.errors.length
    assert_includes engine.errors.first[:error], "boom"
  end

  def test_candidates_without_a_record_or_a_reason_are_dropped
    D::Registry.register(:brgen, lambda { |_ctx|
      [D::Candidate.new(record: nil, reason_key: "x"),
       D::Candidate.new(record: Object.new, reason_key: ""),
       candidate(score: 1.0)]
    })

    assert_equal 1, D::Engine.new(context: context).call.length
  end

  # An actor can be present and still not be a signed-in person: the apps
  # carry an anonymous posting path.
  def test_a_guest_actor_is_not_authenticated
    guest = Object.new
    def guest.guest? = true

    assert context(actor: guest).anonymous?
    refute context(actor: guest).authenticated?
  end

  def test_an_actor_without_a_guest_predicate_counts_as_signed_in
    assert context(actor: Object.new).authenticated?
  end

  def test_no_actor_is_anonymous
    assert context.anonymous?
  end
end
