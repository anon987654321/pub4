# frozen_string_literal: true

require "test_helper"

# A Live post is anonymous (Post#stamp_live_location!). The quick composer used
# to send nearby=true in a hidden field for anyone who had shared a location,
# so their signed-in posts went out anonymous under the name the composer
# showed. Live is now a checkbox the author ticks.
class ComposerNearbyChoiceTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.strict_loading(false).create!(
      email_address: "naer-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
      username: "naer_#{SecureRandom.hex(3)}", guest: false, email_verified_at: Time.current
    )
    @user.update_columns(latitude: 60.39, longitude: 5.32, location_updated_at: Time.current)
    host! "brgen.no"
    post session_path, params: { email_address: @user.email_address, password: "password123" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the composer offers Live as an unticked choice" do
    get root_path

    assert_response :success
    box = Nokogiri::HTML(response.body).at_css(%(dialog input[type="checkbox"][name="post[nearby]"]))
    assert box, "no Live checkbox in the composer"
    refute box["checked"], "Live is ticked before the author chose it"
  end

  test "the Live choice says it posts anonymously within about a kilometre, with its limit" do
    get root_path

    page = Nokogiri::HTML(response.body)
    box = page.at_css(%(dialog input[type="checkbox"][name="post[nearby]"]))
    label = box.ancestors("label").first
    assert_includes label.text, "~1 km"
    assert_includes label.text, Post::LIVE_CONTENT_MAX.to_s
    hint = page.at_css("##{box['aria-describedby']}")
    assert hint, "the choice has no description"
    assert_includes hint.text, Post::LIVE_CONTENT_MAX.to_s
  end

  test "a post without the box ticked keeps its author" do
    post posts_path, params: { post: { content: "Navngitt innlegg #{SecureRandom.hex(3)}", nearby: "false" } }

    written = Post.includes(:user).where(user: @user).order(created_at: :desc).first
    assert written, "expected the post to be saved"
    assert written.attributed?, "the post went out anonymous"
  end
end
