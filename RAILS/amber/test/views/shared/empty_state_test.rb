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

  # body: is the one name for the text; the message: alias had no caller left.
  test "the old message alias renders nothing" do
    render partial: "shared/empty_state", locals: { title: "Nothing here", message: "Old words" }

    assert_select "h2.empty-state-title", text: "Nothing here"
    refute_select ".empty-state-body"
  end
end
