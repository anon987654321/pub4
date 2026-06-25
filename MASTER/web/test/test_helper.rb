# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
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

def stub_master_container
  bus = Class.new do
    def publish(*); end
  end.new
  session = Struct.new(:token_est, :cost).new(0, 0.0)
  agent = Struct.new(:model).new("test/model")
  breaker = Struct.new(:open_models).new([])
  { bus: bus, agent: agent, session: session, breaker: breaker }
end