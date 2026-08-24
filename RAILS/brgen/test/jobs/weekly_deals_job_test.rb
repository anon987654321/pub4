# frozen_string_literal: true

require "test_helper"

class WeeklyDealsJobTest < ActiveSupport::TestCase
  test "sends weekly deals edition to marketing subscribers" do
    edition = NewsletterEdition.create!(
      kind: "weekly_deals",
      city: "bergen",
      edition_date: Date.current,
      subject: "Bergen — picks worth your attention",
      lede: "A handful of offers we would actually click ourselves.",
      stories: [],
      deals: [ { "title" => "Deal", "url" => "https://example.com", "description" => "Good", "price" => "10", "currency" => "NOK", "merchant" => "Shop", "image_url" => "" } ]
    )
    EmailSubscription.create!(
      email: "deals@example.com",
      city: "bergen",
      agreed_to_marketing: true,
      confirmed: true,
      confirmed_at: Time.current
    )

    delivered = false
    original = NewsletterMailer.method(:edition)
    NewsletterMailer.define_singleton_method(:edition) do |*_args|
      Object.new.tap { |mail| mail.define_singleton_method(:deliver_now) { delivered = true } }
    end

    WeeklyDealsJob.perform_now

    NewsletterMailer.define_singleton_method(:edition, original)
    assert delivered
    assert edition.reload.sent_at.present?
  end
end
