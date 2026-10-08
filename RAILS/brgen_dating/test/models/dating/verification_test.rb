# frozen_string_literal: true

require "test_helper"

class Dating::VerificationTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(email_address: "verify_owner@brgen.no", password: "password123", city: @city)
    @reviewer = User.strict_loading(false).create!(email_address: "verify_admin@brgen.no", password: "password123", city: @city)
    @profile = ActsAsTenant.with_tenant(@city) { Dating::Profile.create!(user: @owner, age: 30, visible: false) }
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a request needs a known status, a known pose and a selfie" do
    verification = Dating::Verification.new(profile: @profile, status: "maybe", pose: "wink")

    assert_not verification.valid?
    assert verification.errors.added?(:status, :inclusion, value: "maybe")
    assert verification.errors.added?(:pose, :inclusion, value: "wink")
    assert verification.errors.added?(:selfie, :blank)
  end

  test "every pose drawn for a request is one the model accepts" do
    20.times { assert_includes Dating::Verification::POSES, Dating::Verification.pose_for_request }
  end

  test "a profile may hold only one pending request" do
    request!
    second = build_request

    assert_not second.valid?
    assert second.errors.added?(:base, :already_pending)
  end

  test "a rejected request does not block a new one" do
    request!.reject!(by: @reviewer)

    assert build_request.valid?
  end

  test "approving marks the profile verified and tells its owner" do
    id = request!.id
    found = Dating::Verification.find(id)

    assert_difference "Notification.count", 1 do
      found.approve!(by: @reviewer, note: "")
    end
    found.reload
    assert_equal "verified", found.status
    assert_equal @reviewer.id, found.reviewed_by_id
    assert_not_nil found.reviewed_at
    assert_nil found.review_note
    assert_not_nil @profile.reload.verified_at
    assert_includes Dating::Profile.verified, @profile
  end

  test "rejecting clears the profile's verified mark" do
    @profile.update_column(:verified_at, Time.current)

    request!.reject!(by: @reviewer, note: "ikke samme person")

    assert_nil @profile.reload.verified_at
    assert_not_includes Dating::Profile.verified, @profile
    assert_equal "ikke samme person", Dating::Verification.last.review_note
  end

  private

  def build_request
    Dating::Verification.new(profile: @profile, status: "pending", pose: Dating::Verification::POSES.first).tap do |verification|
      attach_pixel!(verification.selfie)
    end
  end

  def request!
    build_request.tap(&:save!)
  end
end
