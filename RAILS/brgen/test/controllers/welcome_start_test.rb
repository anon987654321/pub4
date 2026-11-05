# frozen_string_literal: true

require "test_helper"

# The first step after the welcome dialog: the city's neighbourhoods, each the
# home feed's own filter, and a few communities to join in place.
class WelcomeStartTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the dialog's primary button links to the first step" do
    get root_path

    assert_select ".welcome-onboarding a.welcome-onboarding-primary[href=?]", welcome_start_path,
                  text: I18n.t("onboarding.first_step")
  end

  test "the first step offers neighbourhoods as feed filters and communities to join" do
    ActsAsTenant.with_tenant(@city) do
      neighborhood = Neighborhood.create!(city: @city, name: "Sandviken", slug: "sandviken-#{SecureRandom.hex(3)}")
      community = Community.create!(name: "Velkommen #{SecureRandom.hex(3)}", slug: "velkommen-#{SecureRandom.hex(4)}")
      user = User.strict_loading(false).create!(email_address: "welcome-#{SecureRandom.hex(4)}@brgen.no",
                                                password: "password123", city: @city)
      post session_path, params: { email_address: user.email_address, password: "password123" }

      get welcome_start_path

      assert_response :success
      assert_select "h1", I18n.t("welcome_start.title")
      assert_select "a[href=?]", root_path(neighborhood_id: neighborhood.id), text: "Sandviken"
      assert_select "form[action=?]", join_community_path(community)
    end
  end
end
