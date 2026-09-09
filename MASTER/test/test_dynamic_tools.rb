# frozen_string_literal: true

require_relative "test_helper"

class TestDynamicTools < Minitest::Test
  def test_registry_rows_empty_when_no_enabled_tools
    rows = Master::Io::DynamicTools.registry_rows
    assert rows.is_a?(Array)
  end

  def test_lookup_missing_returns_nil
    assert_nil Master::Io::DynamicTools.lookup("nonexistent-tool-xyz")
  end
end
