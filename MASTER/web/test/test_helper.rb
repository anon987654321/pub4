# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
ENV["MASTER_AUTH_CONFIG"] ||= File.expand_path("fixtures/master_auth_config.yml", __dir__)
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    setup do
      Rails.application.config.x.master_bootstrap_started = true
      Rails.application.config.x.master_container = stub_master_container
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
  session = Struct.new(:token_est, :cost, :messages).new(0, 0.0, [])
  agent = Struct.new(:model).new("test/model")
  breaker = Struct.new(:open_models).new([])
  personality = Struct.new(:name, :voice, :tts_rate, :tts_pitch).new(
    Master::Voice::Personality::DEFAULT.to_s, Master::Voice::Speech::DEFAULT_VOICE, nil, nil
  )
  gateway = Class.new do
    def receive(channel:, message:, metadata: {})
      Master::Result.ok({ rendered: message.to_s, client_actions: [], metadata: metadata })
    end
  end.new
  skills = Struct.new(:loaded).new([])
  { bus: bus, agent: agent, session: session, breaker: breaker, personality: personality, gateway: gateway, skills: skills }
end