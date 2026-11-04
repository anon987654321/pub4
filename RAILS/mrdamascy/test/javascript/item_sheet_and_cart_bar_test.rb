# frozen_string_literal: true

require "test_helper"
require_relative "stimulus_node"

# item_sheet and cart_bar controllers' own source under node.
class ItemSheetAndCartBarTest < ActiveSupport::TestCase
  include StimulusNode

  test "the sauce cap locks the third chip and says so once" do
    seen = run_stimulus("item_sheet", "item_sheet_sauces.mjs")

    assert_equal({ "locked" => true, "notice" => "two chosen" }, seen["full"])
    assert seen["unlocked"]
    assert_equal "", seen["cleared"]
    assert_equal "15,50 kr", seen["price"], "øre are shown as money() shows them"
  end

  test "the pay-bar pulses only after a cart form succeeds" do
    seen = run_stimulus("cart_bar", "cart_bar_pulse.mjs")

    assert_not seen["refused"], "a refused add must not pulse"
    assert_not seen["other_form"], "a form outside the cart must not pulse"
    assert seen["added"]
    assert_equal "15,50 kr", seen["total"]
  end
end
