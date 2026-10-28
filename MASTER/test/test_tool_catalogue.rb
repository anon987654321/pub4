# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/builder"

class TestToolCatalogue < Minitest::Test
  BUILDER = Master::Builder

  def row(name, overrides = {})
    {
      "name" => name,
      "elevated" => false,
      "visitor" => false,
      "default" => true,
      "description" => "A registered tool"
    }.merge(overrides)
  end

  def test_live_tool_catalogue_matches_every_factory_and_special_tool
    definitions = Master.tools_config(root: Master::ROOT)

    assert BUILDER.validate_tool_catalogue!(definitions)
  end

  def test_non_array_catalogue_is_not_treated_as_an_empty_toolset
    [nil, {}, "tools"].each do |value|
      error = assert_raises(ArgumentError) do
        BUILDER.validate_tool_catalogue!(value, registry: {}, special_names: [])
      end
      assert_match(/non-empty list of tool mappings/, error.message)
    end
  end

  def test_unknown_tool_name_fails_even_when_disabled
    error = assert_raises(ArgumentError) do
      BUILDER.validate_tool_catalogue!(
        [row("GhostTool", "default" => false)],
        registry: {},
        special_names: []
      )
    end

    assert_match(/tools without a builder: GhostTool/, error.message)
  end

  def test_duplicate_tool_names_are_rejected
    error = assert_raises(ArgumentError) do
      BUILDER.validate_tool_catalogue!(
        [row("ReadFile"), row("ReadFile")],
        registry: { "ReadFile" => ->(*) {} },
        special_names: []
      )
    end

    assert_match(/duplicate tool name\(s\): ReadFile/, error.message)
  end

  def test_unknown_tool_fields_are_rejected
    error = assert_raises(ArgumentError) do
      BUILDER.validate_tool_catalogue!(
        [row("ReadFile", "tier" => "safe")],
        registry: { "ReadFile" => ->(*) {} },
        special_names: []
      )
    end

    assert_match(/row 1 has unknown field\(s\): tier/, error.message)
  end

  def test_non_string_tool_names_are_rejected
    error = assert_raises(ArgumentError) do
      BUILDER.validate_tool_catalogue!(
        [row(123)],
        registry: {},
        special_names: []
      )
    end

    assert_match(/row 1 has invalid name 123/, error.message)
  end

  def test_invalid_exposure_flag_is_rejected
    error = assert_raises(ArgumentError) do
      BUILDER.validate_tool_catalogue!(
        [row("ReadFile", "visitor" => "false")],
        registry: { "ReadFile" => ->(*) {} },
        special_names: []
      )
    end

    assert_match(/ReadFile\.visitor must be boolean/, error.message)
  end

  def test_factory_missing_from_catalogue_is_reported
    error = assert_raises(ArgumentError) do
      BUILDER.validate_tool_catalogue!(
        [row("ReadFile")],
        registry: {
          "ReadFile" => ->(*) {},
          "WriteFile" => ->(*) {}
        },
        special_names: []
      )
    end

    assert_match(/builder tools missing from data\/tools\.yml: WriteFile/, error.message)
  end

  def test_special_ask_llm_obeys_its_catalogue_default
    assert BUILDER.tool_enabled?([row("AskLlm")], "AskLlm")
    refute BUILDER.tool_enabled?([row("AskLlm", "default" => false)], "AskLlm")
    refute BUILDER.tool_enabled?([], "AskLlm")
    assert BUILDER.tool_enabled?(nil, "AskLlm", missing_default: true)
  end
end
