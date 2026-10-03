# frozen_string_literal: true

require "test_helper"

# Smoke: partner program models + attribution still work after UI landing.
class PartnerMarketingUiTest < ActiveSupport::TestCase
  test "partner tables and models load" do
    assert defined?(Partner::Program)
    assert defined?(Partner::Membership)
    assert defined?(Partner::Click)
    assert defined?(Partner::Conversion)
    assert defined?(PartnerMarketing)
  end

  test "public programs disappear with their store owner" do
    city = City.first || City.create!(
      name: "Bergen", domain: "brgen.no", slug: "bergen", country_code: "NO", locale: "nb", currency: "NOK"
    )
    owner = User.create!(
      email_address: "partner-owner-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", username: "partner_owner_#{SecureRandom.hex(3)}", city: city, guest: false
    )
    store = Marketplace::Store.create!(
      owner: owner, name: "Partner Store #{SecureRandom.hex(3)}", slug: "partner-store-#{SecureRandom.hex(4)}", active: true
    )
    program = Partner::Program.create!(
      store: store, city: city, name: "Program", status: "open",
      commission_model: "cpa_percent", commission_rate: 500, attribution_hours: 24, hold_days: 7
    )

    assert_includes Partner::Program.publicly_visible, program

    owner.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)
    refute_includes Partner::Program.publicly_visible, program
  end

  test "earning stops when either side leaves the service" do
    owner = User.create!(
      email_address: "earning-owner-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", username: "earning_owner_#{SecureRandom.hex(3)}", guest: false
    )
    partner = User.create!(
      email_address: "earning-partner-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", username: "earning_partner_#{SecureRandom.hex(3)}", guest: false
    )
    store = Marketplace::Store.create!(
      owner: owner, name: "Earning Store #{SecureRandom.hex(3)}", slug: "earning-store-#{SecureRandom.hex(4)}", active: true
    )
    program = Partner::Program.create!(
      store: store, name: "Earning Program", status: "open",
      commission_model: "cpa_percent", commission_rate: 500, attribution_hours: 24, hold_days: 7
    )
    membership = Partner::Membership.create!(program: program, user: partner, status: "approved")

    assert_predicate membership, :earning?

    partner.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)
    assert_not membership.reload.earning?

    partner.update_columns(deleted_at: nil, deletion_scheduled_at: nil)
    owner.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)
    assert_not membership.reload.earning?
  end

  test "program commission math stays integer" do
    program = Partner::Program.new(
      name: "Test",
      commission_model: "cpa_percent",
      commission_rate: 1_000, # 10%
      attribution_hours: 720,
      hold_days: 30,
      status: "open"
    )
    assert_equal 250, program.commission_for(2_500)
  end
end
