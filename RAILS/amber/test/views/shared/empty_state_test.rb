# frozen_string_literal: true

require "test_helper"

class SharedEmptyStateTest < ActionView::TestCase
  test "legacy String actions local logs its deprecation and remains rendered" do
    warnings = []

    Rails.logger.stub(:warn, ->(message) { warnings << message }) do
      render partial: "shared/empty_state",
             locals: { title: "Nothing here", actions: "Legacy action" }
    end

    assert_select ".empty-state-actions", text: "Legacy action"
    assert_equal 1, warnings.length
    assert_includes warnings.first, "DEPRECATION: shared/empty_state actions:"
    assert_includes warnings.first, "action: { label:, path: }"
  end
end
