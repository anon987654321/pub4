# frozen_string_literal: true

require "test_helper"

# A business owner asks for the badge on the shop's own host, and only the admin
# the moderation queue already names decides.
class BusinessVerificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = make_user("bvc_owner")
    @stranger = make_user("bvc_stranger")
    @admin = make_user("bvc_admin")
    @store = Marketplace::Store.create!(owner: @owner, name: "Butikken #{SecureRandom.hex(2)}", slug: "bvc-#{SecureRandom.hex(4)}")
    @marketplace_host = "#{Brgen::DomainRegistry::MARKETPLACE_SUBDOMAINS.first}.brgen.no"
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    ENV.delete("BRGEN_ADMIN_EMAIL")
  end

  def make_user(name)
    User.strict_loading(false).create!(email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false)
  end

  def sign_in_as(user, host: "brgen.no")
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! host
  end

  def ask(params = { legal_name: "Butikken AS", organisation_number: "923609016" })
    post business_verifications_path(kind: "store", business_id: @store.id), params: { business_verification: params }
  end

  test "the owner sees the way to ask, files a request, and sees it waiting" do
    sign_in_as(@owner, host: @marketplace_host)
    get marketplace.shop_path(@store.slug)
    assert_response :success
    assert_includes response.body, I18n.t("business_verifications.request")

    get new_business_verification_path(kind: "store", business_id: @store.id)
    assert_response :success

    assert_difference -> { BusinessVerification.pending.count }, 1 do
      ask
    end
    assert_redirected_to marketplace.shop_path(@store.slug)

    get marketplace.shop_path(@store.slug)
    assert_includes response.body, I18n.t("business_verifications.pending")
  end

  test "an invalid organisation number is sent back to the form" do
    sign_in_as(@owner)
    assert_no_difference -> { BusinessVerification.count } do
      ask(legal_name: "Butikken AS", organisation_number: "123456789")
    end
    assert_response :unprocessable_entity
  end

  test "somebody else cannot ask for the owner's shop" do
    sign_in_as(@stranger)
    assert_no_difference -> { BusinessVerification.count } do
      ask
    end
    assert_equal I18n.t("shared.flash.not_authorized"), flash[:alert]
  end

  test "only the admin reviews, and approval puts the mark on the shop" do
    verification = BusinessVerification.create!(business: @store, requested_by: @owner,
                                                legal_name: "Butikken AS", organisation_number: "923609016")

    sign_in_as(@owner)
    get admin_business_verifications_path
    assert_equal I18n.t("shared.flash.not_authorized"), flash[:alert]

    ENV["BRGEN_ADMIN_EMAIL"] = @admin.email_address
    sign_in_as(@admin)
    get admin_business_verifications_path
    assert_response :success
    assert_includes response.body, "923609016"

    patch admin_business_verification_path(verification, decision: "approve")
    assert_equal "verified", verification.reload.status
    assert Marketplace::Store.find(@store.id).verified?

    host! @marketplace_host
    get marketplace.shop_path(@store.slug)
    assert_includes response.body, I18n.t("business_verifications.badge")
  end
end
