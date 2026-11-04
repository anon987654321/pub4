# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../javascript/stimulus_node"

# The staff board is pushed: new orders and moves arrive without a tap.
class StaffBoardLiveTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper
  include StimulusNode

  test "a new order and each move redraw the board grid" do
    kitchen = seed_kitchen!
    order = nil
    assert_turbo_stream_broadcasts("staff_board", count: 1) { order = seed_order!(kitchen:) }

    streams = capture_turbo_stream_broadcasts("staff_board") { order.advance! }
    assert_equal "board_grid", streams.sole["target"]
    assert_includes streams.sole.to_html, "order_card_#{order.id}"

    assert_empty capture_turbo_stream_broadcasts("staff_board") { order.update!(phone: "90000099") }
  end

  test "the board subscribes and each card says how long it has waited" do
    order = travel_to(12.minutes.ago) { seed_order! }
    staff_sign_in
    get staff_board_url
    page = Nokogiri::HTML(response.body)

    assert page.at_css("turbo-cable-stream-source")
    age = page.at_css("#order_card_#{order.id} time.board-card-age")
    assert_equal I18n.t("staff.age", minutes: 12), age.text
    assert_equal order.placed_at.iso8601, age["datetime"]
  end

  test "a newly placed order chimes, a moving one does not, and ages tick" do
    seen = run_stimulus("board", "board_chime.mjs")

    assert_equal 0, seen["moved"]
    assert_equal 1, seen["landed"]
    assert_equal "7 min siden", seen["age"]
  end
end
