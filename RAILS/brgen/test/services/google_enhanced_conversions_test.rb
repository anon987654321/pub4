# frozen_string_literal: true

require "test_helper"

# The upload carries a customer's hashed email and phone. Whether it may is a
# consent question, and no order carries a consent flag yet — so the case that
# matters most is the one where consent is unknown.
class GoogleEnhancedConversionsTest < ActiveSupport::TestCase
  Order = Struct.new(:id, :gclid, :email, :phone, :ad_user_data_consent, :total_cents, :currency, :paid_at,
                     keyword_init: true)

  def order(consent:)
    Order.new(id: 1, gclid: "abc123", email: "Kunde@Example.com", phone: "+4712345678",
              ad_user_data_consent: consent, total_cents: 19_900, currency: "NOK", paid_at: Time.current)
  end

  def event_for(consent)
    GoogleEnhancedConversions.send(:build_event, order(consent:))
  end

  test "sends no user identifiers when consent is unknown" do
    event = event_for(nil)
    assert_nil event["userData"], "hashed email or phone uploaded without a consent signal"
    assert_nil event["consent"]
  end

  test "sends no user identifiers when consent is denied" do
    event = event_for(false)
    assert_nil event["userData"]
    assert_equal "CONSENT_DENIED", event.dig("consent", "adUserData")
  end

  test "sends hashed identifiers when consent is granted" do
    event = event_for(true)
    assert_equal "CONSENT_GRANTED", event.dig("consent", "adUserData")
    identifiers = event.dig("userData", "userIdentifiers")
    assert identifiers.present?, "consented order sent no identifiers"
    assert_not identifiers.to_s.include?("Kunde@Example.com"), "raw email left in the payload"
  end

  # The gclid is Google's own click id, not the customer's contact details, and
  # it rides on the conversion regardless.
  test "still reports the conversion when consent is unknown" do
    event = event_for(nil)
    assert_equal "abc123", event.dig("adIdentifiers", "gclid")
  end
end
