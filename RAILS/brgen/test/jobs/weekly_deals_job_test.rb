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

  test "does not deliver weekly deals to a departing account's address" do
    edition = NewsletterEdition.create!(
      kind: "weekly_deals",
      city: "bergen",
      edition_date: Date.current,
      subject: "Bergen — picks worth your attention",
      lede: "A few offers.",
      stories: [],
      deals: []
    )
    user = User.create!(email_address: "weekly-leaving-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", city: City.find_by(domain: "brgen.no"))
    EmailSubscription.create!(email: user.email_address, city: "bergen", agreed_to_marketing: true, confirmed: true, confirmed_at: Time.current)
    user.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    delivered = false
    original = NewsletterMailer.method(:edition)
    NewsletterMailer.define_singleton_method(:edition) do |*_args|
      Object.new.tap { |mail| mail.define_singleton_method(:deliver_now) { delivered = true } }
    end

    WeeklyDealsJob.perform_now

    NewsletterMailer.define_singleton_method(:edition, original)
    assert_not delivered
  end

end
