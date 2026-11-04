# frozen_string_literal: true

require "test_helper"

# What the public tracking page tells the customer about their order.
class TrackPageTest < ActionDispatch::IntegrationTest
  def timeline(order)
    get track_url(order.tracking_token)
    assert_response :success
    Nokogiri::HTML(response.body).css("ol.timeline > li")
  end

  test "finished steps say so in words, not only in colour" do
    steps = timeline(seed_order!(state: "preparing"))
    done = I18n.t("orders.step_done")

    marked = (0...steps.size).select { |i| steps[i].text.include?(done) }
    assert_equal [0, 1], marked, "placed and confirmed are done; preparing is current"
  end
  test "a pickup order ends with collection, not delivery" do
    labels = timeline(seed_order!(state: "picked_up", delivery_mode: "pickup")).css(".step-label").map(&:text)

    assert_equal I18n.t("orders.states.picked_up"), labels.last
    assert_not_includes labels, I18n.t("orders.states.delivered")
  end

  test "a delivery order still ends at the door" do
    steps = timeline(seed_order!(state: "picked_up"))

    assert_equal I18n.t("orders.states.delivered"), steps.last.at_css(".step-label").text
    assert_equal "step", steps[3]["aria-current"], "mid-courier the ready step stays current"
  end
end
