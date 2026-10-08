# frozen_string_literal: true

require "test_helper"

class Marketplace::GigDetailTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @category = Marketplace::Category.create!(name: "Kategori #{SecureRandom.hex(4)}")
    @lister = User.strict_loading(false).create!(
      email_address: "gig_detail@brgen.no", password: "password123", city: @city
    )
    @listing = ActsAsTenant.with_tenant(@city) do
      Marketplace::Listing.create!(category: @category, user: @lister, title: "Bartender fredag", kind: "gig")
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a gig starting in the past is refused when it is created" do
    detail = Marketplace::GigDetail.new(listing: @listing, starts_at: 1.hour.ago)

    assert_not detail.valid?
    assert detail.errors.added?(:starts_at, :in_the_past)
  end

  test "a gig that has since happened can still be edited" do
    detail = Marketplace::GigDetail.create!(listing: @listing, starts_at: 1.hour.from_now)

    travel 2.hours do
      assert detail.update(hours: 4)
    end
  end

  test "hours must be positive and pay cannot be negative" do
    detail = Marketplace::GigDetail.new(listing: @listing, hours: 0, pay_cents: -1)

    assert_not detail.valid?
    assert detail.errors.added?(:hours, :greater_than, value: 0, count: 0)
    assert detail.errors.added?(:pay_cents, :greater_than_or_equal_to, value: -1, count: 0)
  end

  test "a gig with nothing but a listing is valid, and shows no pay" do
    detail = Marketplace::GigDetail.new(listing: @listing)

    assert detail.valid?
    assert_nil detail.pay_display
    assert_equal Shared::MoneyDisplay.format(1_500_00), Marketplace::GigDetail.new(pay_cents: 1_500_00).pay_display
  end
end
