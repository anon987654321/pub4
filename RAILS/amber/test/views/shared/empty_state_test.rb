# frozen_string_literal: true

require "test_helper"

class SharedEmptyStateTest < ActionView::TestCase
  test "hash action renders one clear call to action" do
    render partial: "shared/empty_state",
           locals: {
             title: "Nothing here",
             body: "Start by adding an item.",
             action: { label: "Browse items", path: "/items" },
           }

    assert_select "section.empty-state[role=status]"
    assert_select "a.empty-state-action[href='/items']", text: "Browse items"
    refute_select ".empty-state-actions"
  end
end
