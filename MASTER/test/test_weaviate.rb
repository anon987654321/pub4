# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/reach/weaviate"

class WeaviateTest < Minitest::Test
  def test_indexed_returns_false_when_unreachable
    client = Master::Reach::Weaviate.new(host: "http://127.0.0.1:1")
    refute client.indexed?(class_name: "Document", object_id: "00000000-0000-0000-0000-000000000000")
  end
end