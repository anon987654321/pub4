# frozen_string_literal: true

require "test_helper"

# The account page lists the people this account blocks, each with a way to
# lift the block, without visiting the person's profile.
class AccountBlockedPeopleTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def person(name)
    User.strict_loading(false).create!(email_address: "blokk-#{SecureRandom.hex(6)}@brgen.no",
                                       password: "password123", city: @city, display_name: name)
  end

  test "blocked people are listed with an unblock button that lifts the block" do
    me = person("Blokkerer")
    pest = person("Plageånd")
    me.block!(pest)
    post session_path, params: { email_address: me.email_address, password: "password123" }

    get account_path

    assert_select "section a[href=?]", user_path(pest), text: "Plageånd"
    assert_select "form[action=?]", unblock_user_path(pest)

    delete unblock_user_path(pest), headers: { "HTTP_REFERER" => account_url }
    assert_redirected_to account_url
    assert_not me.reload.blocking?(pest)
  end

  test "an account that blocks nobody says so" do
    me = person("Fredelig")
    post session_path, params: { email_address: me.email_address, password: "password123" }

    get account_path

    assert_includes response.body, I18n.t("account_blocks.none")
  end
end
