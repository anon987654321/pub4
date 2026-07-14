# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActionDispatch::IntegrationTest
  parallelize(workers: :number_of_processors)
end