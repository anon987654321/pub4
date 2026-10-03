# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "shared/test_defaults"
require "minitest/mock"

module ActiveSupport
  class TestCase
    Shared::TestDefaults.install!(self)
  end
end
