# frozen_string_literal: true

require "test_helper"

# posts#share told every refusal "could not create draft": its specific
# English defaults sat behind a key that always resolved.
class PostShareFlashTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
    @member = User.create!(email_address: "deler-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
                           username: "deler_#{SecureRandom.hex(3)}")
    post session_path, params: { email_address: @member.email_address, password: "password123" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "an empty share says there is nothing to share, in the locale" do
    post share_post_path

    assert_redirected_to new_post_path
    assert_equal I18n.t("flash.share_nothing"), flash[:alert]
  end
end
