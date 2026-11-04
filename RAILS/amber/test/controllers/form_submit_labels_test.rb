# frozen_string_literal: true

require "test_helper"

# The item and outfit forms used a bare f.submit, which builds "Create
# Item" / "Update Outfit" from the English model name in every locale.
class FormSubmitLabelsTest < ActionDispatch::IntegrationTest
  test "the item and outfit forms submit with translated labels" do
    email = "fs-#{SecureRandom.hex(4)}@example.test"
    User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }

    { new_item_path => "items.save", new_outfit_path => "outfits.save" }.each do |path, key|
      get path, params: { locale: "nb" }
      assert_response :success
      assert_select "input[type=submit][value=?]", I18n.t(key, locale: :nb)
    end
  end
end
