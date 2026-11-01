# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../MASTER/checks/lib/rendered/accessibility_tree"

class AccessibilityTreeCheckTest < Minitest::Test
  def test_flags_unnamed_interactive_controls_and_informative_images
    nodes = [
      { "nodeId" => "button-1", "ignored" => false, "role" => { "value" => "button" },
        "name" => { "value" => "" } },
      { "nodeId" => "image-1", "ignored" => false, "role" => { "value" => "image" },
        "name" => { "value" => "  " } },
      { "nodeId" => "link-1", "ignored" => false, "role" => { "value" => "link" },
        "name" => { "value" => "Open marketplace" } }
    ]

    missing = Deploy::AccessibilityTreeCheck.unnamed_nodes(nodes)

    assert_equal [
      { "role" => "button", "node_id" => "button-1" },
      { "role" => "image", "node_id" => "image-1" }
    ], missing
  end

  def test_ignores_decorative_or_noninteractive_nodes
    nodes = [
      { "nodeId" => "decorative-1", "ignored" => true, "role" => { "value" => "image" },
        "name" => { "value" => "" } },
      { "nodeId" => "generic-1", "ignored" => false, "role" => { "value" => "generic" },
        "name" => { "value" => "" } }
    ]

    assert_empty Deploy::AccessibilityTreeCheck.unnamed_nodes(nodes)
  end
end
