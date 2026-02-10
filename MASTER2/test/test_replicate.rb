# frozen_string_literal: true

require_relative "test_helper"

class TestReplicate < Minitest::Test
  def test_responds_to_public_api
    assert_respond_to MASTER::Replicate, :predict
  end

  def test_replicate_module_exists
    assert defined?(MASTER::Replicate), "MASTER::Replicate should be defined"
  end
end
