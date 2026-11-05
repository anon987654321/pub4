# frozen_string_literal: true

require "test_helper"
require_relative "stimulus_node"

# print_controller's own source under node (print_press.mjs): it shows its
# button once it runs and prints the page when pressed.
class PrintControllerTest < ActiveSupport::TestCase
  include StimulusNode

  test "the button shows itself and prints the page" do
    seen = run_stimulus("print", "print_press.mjs")

    assert_equal false, seen["hidden"]
    assert_equal 1, seen["printed"]
  end
end
