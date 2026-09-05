# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
ENV["MASTER_AUTH_CONFIG"] ||= File.expand_path("master_auth_config.yml", __dir__)
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # One process. This suite is not parallelisable, and running it in eight was
    # producing failures that belonged to no test.
    #
    # Three things here are process-global or on disk, shared by every worker:
    # the pairing store at .master/pairing (PairControllerTest#teardown rm_rf's
    # it, so one worker deletes the code another just issued), Fiber storage —
    # Fiber[:master_visitor] is set process-wide when a Master::CLI is built and
    # outlives the test that built it — and the stubbed container hung off
    # Rails.application.config.
    #
    # The cost is nothing: 76 tests finish in under a second either way.
    parallelize(workers: 1)

    setup do
      # Rate limits are Rails.cache counters keyed by remote IP, and every
      # integration test requests from 127.0.0.1 inside one process. Without this
      # the pairing budget (8 redeems a minute) is spent by whichever tests ran
      # first and the rest 429 — so PairControllerTest failed on its position in
      # the run rather than on anything it asserts, differently on every seed.
      Rails.cache.clear
      Rails.application.config.x.master_bootstrap_started = true
      Rails.application.config.x.master_container = stub_master_container
      # set_locale writes I18n.locale on the test thread and leaves it there.
      # An English Accept-Language test would otherwise leak :en into the next
      # case, which is the same per-thread leftover the controller comment
      # exists to stop in production.
      I18n.locale = I18n.default_locale
    end
  end
end

TEST_WEB_TOKEN = MasterWebToken.read

def auth_headers
  { "X-Token" => TEST_WEB_TOKEN }
end

def stub_master_container
  bus = Class.new do
    def publish(*); end
  end.new
  # messages and token_est mirror Trace::Session, which takes an optional
  # conversation key on both. A plain Struct reader takes no arguments, so
  # /chat/history — the one caller that passes the browser's conversation id —
  # raised ArgumentError against this double while the real Session handled it.
  # A double that has drifted from the API it stands in for measures nothing.
  session = Struct.new(:token_est_value, :cost, :messages_value) do
    def messages(_key = nil) = messages_value
    def token_est(_key = nil) = token_est_value
  end.new(0, 0.0, [])
  agent = Struct.new(:model).new("test/model")
  breaker = Struct.new(:open_models).new([])
  personality = Struct.new(:name, :voice, :tts_rate, :tts_pitch).new(
    Master::Voice::Personality::DEFAULT.to_s, Master::Voice::Speech::DEFAULT_VOICE, nil, nil
  )
  gateway = Class.new do
    def receive(channel:, message:, metadata: {})
      Master::Result.ok({ rendered: message.to_s, client_actions: [], metadata: })
    end
  end.new
  skills = Struct.new(:loaded).new([])
  { bus:, agent:, session:, breaker:, personality:, gateway:, skills: }
end
