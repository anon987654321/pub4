# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestContextWindow < Minitest::Test
  def test_public_surface_stays_below_god_class_threshold
    assert_operator Master::Now::ContextWindow.public_instance_methods(false).size, :<=, 10
  end
end
