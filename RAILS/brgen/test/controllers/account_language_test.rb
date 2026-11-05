# frozen_string_literal: true

require "test_helper"

# An account can choose its language on the account page; the choice is kept
# on the user and wins over the domain's language until it is cleared.
class AccountLanguageTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
    @user = User.strict_loading(false).create!(email_address: "sprak-#{SecureRandom.hex(4)}@brgen.no",
                                               password: "password123", city: @city)
    post session_path, params: { email_address: @user.email_address, password: "password123" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "choosing English is remembered on the account and serves English on brgen.no" do
    get account_path
    assert_select "form[action=?] input[type=radio][name=locale]", account_language_path, 3
    assert_select "h2", I18n.t("account_language.heading", locale: :nb)

    patch account_language_path, params: { locale: "en" }
    assert_equal "en", @user.reload.locale

    get account_path
    assert_select "h2", I18n.t("account_language.heading", locale: :en)
    assert_select "html[lang=en]"
  end

  test "following the site clears the choice and brgen.no is Norwegian again" do
    @user.update!(locale: "en")

    patch account_language_path, params: { locale: "" }
    assert_nil @user.reload.locale

    get account_path
    assert_select "h2", I18n.t("account_language.heading", locale: :nb)
  end

  test "a language the app does not ship is refused" do
    patch account_language_path, params: { locale: "de" }

    assert_response :unprocessable_content
    assert_nil @user.reload.locale
  end
end
