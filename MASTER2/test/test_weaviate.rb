# frozen_string_literal: true

require_relative "test_helper"

class TestWeaviate < Minitest::Test
  def test_responds_to_public_api
    assert_respond_to MASTER::Weaviate, :store
    assert_respond_to MASTER::Weaviate, :search
  end

  def test_weaviate_module_exists
    assert defined?(MASTER::Weaviate), "MASTER::Weaviate should be defined"
  end
end
