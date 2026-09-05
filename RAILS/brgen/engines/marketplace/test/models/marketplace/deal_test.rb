# frozen_string_literal: true

require "test_helper"

class Marketplace::DealTest < ActiveSupport::TestCase
  test "ends_in is nil without an end" do
    assert_nil Marketplace::Deal.new(headline: "Tilbud").ends_in
  end

  test "ends_in is the remaining seconds while the deal is open" do
    remaining = Marketplace::Deal.new(headline: "Tilbud", ends_at: 2.hours.from_now).ends_in

    assert remaining
    assert_in_delta 2.hours, remaining, 2
  end

  test "ends_in is nil once the deal has ended" do
    assert_nil Marketplace::Deal.new(headline: "Tilbud", ends_at: 1.hour.ago).ends_in
  end

  test "countdown copy resolves in both shipped locales" do
    %i[nb en].each do |locale|
      assert I18n.exists?("marketplace.deals.ends_in", locale: locale), locale
      assert I18n.exists?("marketplace.deals.featured", locale: locale), locale
    end
  end
end
