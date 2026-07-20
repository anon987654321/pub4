# frozen_string_literal: true

require "ostruct"
require "test_helper"

class DailyDigestJobTest < ActiveSupport::TestCase
  test "sends composed edition to marketing subscribers" do
    edition = NewsletterEdition.create!(
      kind: "daily",
      city: "bergen",
      edition_date: Date.current,
      subject: "Bergen — today",
      lede: "A short list of what people are talking about.",
      stories: [],
      deals: []
    )
    subscription = EmailSubscription.create!(
      email: "news@example.com",
      city: "bergen",
      agreed_to_marketing: true,
      confirmed: true,
      confirmed_at: Time.current
    )

    delivered = false
    singleton = class << NewsletterMailer; self; end
    original = NewsletterMailer.method(:edition)
    NewsletterMailer.define_singleton_method(:edition) do |*_args|
      Object.new.tap { |mail| mail.define_singleton_method(:deliver_now) { delivered = true } }
    end

    DailyDigestJob.perform_now

    singleton.send(:define_method, :edition, original)
    assert delivered
    assert edition.reload.sent_at.present?
    assert subscription.persisted?
  end
end
