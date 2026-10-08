# frozen_string_literal: true

require "test_helper"

class Marketplace::JobDetailTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @category = Marketplace::Category.create!(name: "Kategori #{SecureRandom.hex(4)}")
    @lister = User.strict_loading(false).create!(
      email_address: "job_detail@brgen.no", password: "password123", city: @city
    )
    @listing = ActsAsTenant.with_tenant(@city) do
      Marketplace::Listing.create!(category: @category, user: @lister, title: "Kokk søkes", kind: "job")
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a salary range running backwards is refused" do
    detail = Marketplace::JobDetail.new(listing: @listing, salary_min_cents: 50_000_00, salary_max_cents: 40_000_00)

    assert_not detail.valid?
    assert detail.errors.added?(:salary_max_cents, :below_minimum)
  end

  test "an advert saying nothing about pay is valid" do
    detail = Marketplace::JobDetail.new(listing: @listing)

    assert detail.valid?
    assert_nil detail.salary_display
  end

  test "the employment type is one the form offers and the employer name is bounded" do
    detail = Marketplace::JobDetail.new(listing: @listing, employment_type: "forever", employer: "x" * 121)

    assert_not detail.valid?
    assert detail.errors.added?(:employment_type, :inclusion, value: "forever")
    assert detail.errors.added?(:employer, :too_long, count: 120)
  end

  test "salary display shows a range, or whichever end is given" do
    min = Shared::MoneyDisplay.format(40_000_00)
    max = Shared::MoneyDisplay.format(50_000_00)

    range = Marketplace::JobDetail.new(salary_min_cents: 40_000_00, salary_max_cents: 50_000_00)

    assert_equal "#{min}–#{max}", range.salary_display
    assert_equal min, Marketplace::JobDetail.new(salary_min_cents: 40_000_00).salary_display
    assert_equal max, Marketplace::JobDetail.new(salary_max_cents: 50_000_00).salary_display
  end
end
