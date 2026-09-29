# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"

class TestNamespaceRatchet < Minitest::Test
  TOOL = File.expand_path("../lib/operator/namespace_ratchet.rb", __dir__)

  def test_tool_entrypoint_delegates_to_the_live_ratchet
    assert_path_exists TOOL

    out, err, status = Open3.capture3(RbConfig.ruby, TOOL, "--json")

    assert status.success?, "namespace ratchet failed: #{out}#{err}"
    payload = JSON.parse(out)
    assert_kind_of Hash, payload
    assert payload.key?("recorded")
    assert payload.key?("actual")
    refute_empty payload.fetch("recorded")
    assert_equal payload.fetch("recorded").keys.sort, payload.fetch("actual").keys.sort
  end
end
