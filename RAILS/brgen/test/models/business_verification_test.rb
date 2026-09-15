# frozen_string_literal: true

require "test_helper"

class BusinessVerificationTest < ActiveSupport::TestCase
  # Equinor ASA, as Brønnøysundregistrene lists it.
  VALID_NUMBER = "923609016"

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = User.strict_loading(false).create!(
      email_address: "bv_owner@brgen.no", password: "password123", username: "bv_owner", guest: false
    )
    @stranger = User.strict_loading(false).create!(
      email_address: "bv_stranger@brgen.no", password: "password123", username: "bv_stranger", guest: false
    )
    @reviewer = User.strict_loading(false).create!(
      email_address: "bv_reviewer@brgen.no", password: "password123", username: "bv_reviewer", guest: false
    )
    @store = Marketplace::Store.create!(owner: @owner, name: "Butikken #{SecureRandom.hex(2)}", slug: "bv-#{SecureRandom.hex(4)}")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def request_for(business, by:, number: VALID_NUMBER)
    BusinessVerification.new(business: business, requested_by: by, legal_name: "Butikken AS", organisation_number: number)
  end

  test "the organisation number follows the register's mod-11 rule" do
    assert BusinessVerification.organisation_number_valid?(VALID_NUMBER)
    assert_not BusinessVerification.organisation_number_valid?("923609017")
    assert_not BusinessVerification.organisation_number_valid?("92360901")
    assert_not BusinessVerification.organisation_number_valid?("92360901a")
    assert request_for(@store, by: @owner, number: "923 609 016").valid?
  end

  test "only the owner asks, and one request waits at a time" do
    assert_not request_for(@store, by: @stranger).valid?

    request_for(@store, by: @owner).save!
    second = request_for(@store, by: @owner)
    assert_not second.valid?
    assert_includes second.errors.details[:base].map { |detail| detail[:error] }, :already_pending
  end

  test "approval marks the business, rejection clears it, and the owner hears both" do
    verification = request_for(@store, by: @owner)
    verification.save!

    verification.approve!(by: @reviewer)
    assert_equal "verified", verification.reload.status
    assert Marketplace::Store.find(@store.id).verified?
    assert Notification.where(user_id: @owner.id, kind: "alert").exists?

    verification.reject!(by: @reviewer, note: I18n.t("business_verifications.rejected_body"))
    assert_not Marketplace::Store.find(@store.id).verified?
  end

  test "a restaurant is verified by the same review" do
    restaurant = Takeaway::Restaurant.create!(
      user: @owner, name: "Kjokken #{SecureRandom.hex(3)}", address: "Marken 4", cuisine_type: "Norwegian", city: @city
    )
    verification = request_for(restaurant, by: @owner)
    verification.save!
    verification.approve!(by: @reviewer)

    assert Takeaway::Restaurant.find(restaurant.id).verified?
  end

  test "a business type outside the admitted two is refused" do
    verification = BusinessVerification.new(business_type: "User", business_id: @owner.id, requested_by: @owner,
                                            legal_name: "Meg AS", organisation_number: VALID_NUMBER)
    assert_not verification.valid?
  end
end
