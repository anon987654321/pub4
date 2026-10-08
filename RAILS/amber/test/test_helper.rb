# frozen_string_literal: true

# Coverage starts before Rails boots so application, engine and view execution cannot disappear behind load-time blind spots.
require_relative "../../__shared/test/coverage"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "shared/test_defaults"

module ActiveSupport
  class TestCase
    Shared::TestDefaults.install!(self)
  end
end
