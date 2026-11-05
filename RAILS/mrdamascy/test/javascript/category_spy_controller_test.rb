# frozen_string_literal: true

require "test_helper"
require_relative "stimulus_node"

# category_spy's own source under node, against a stand-in observer.
class CategorySpyControllerTest < ActiveSupport::TestCase
  include StimulusNode

  test "the chip of the section in view is the current one" do
    seen = run_stimulus("category_spy", "category_spy_scroll.mjs")

    assert_equal [ "true", nil ], seen["first"]
    assert_equal [ nil, "true" ], seen["then"]
  end
end
