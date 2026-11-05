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
    assert_equal [ 0, 1 ], marked, "placed and confirmed are done; preparing is current"
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
  test "the review stars are radios named in words" do
    order = seed_order!(state: "delivered")
    get track_url(order.tracking_token)
    radios = Nokogiri::HTML(response.body).css("input[type=radio][name=rating]")

    assert_equal %w[5 4 3 2 1], radios.map { |r| r["value"] }
    assert_includes radios.first.parent.text, "5 av 5 stjerner"
  end
  test "a given review is shown back instead of a fresh form" do
    order = seed_order!(state: "delivered")
    Review.create!(order:, user: order.user, rating: 4, body: "Toum til himmelen")

    get track_url(order.tracking_token)
    page = Nokogiri::HTML(response.body)

    assert_nil page.at_css("form.review-form")
    assert_includes page.at_css(".review-given").text, "4 av 5 stjerner"
    assert_includes response.body, "Toum til himmelen"
  end

  test "the page hands the tracker its status url and names the state politely" do
    order = seed_order!(state: "preparing")
    get track_url(order.tracking_token)
    page = Nokogiri::HTML(response.body)

    assert_equal track_status_path(order.tracking_token), page.at_css("[data-controller=track]")["data-track-url-value"]
    status = page.at_css("[data-controller=track] [role=status]")
    assert_equal "polite", status["aria-live"]
    assert_equal "Status: #{I18n.t('orders.states.preparing')}", status.text
  end
end
