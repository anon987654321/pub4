# frozen_string_literal: true

require "test_helper"

class PlaylistVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = User.strict_loading(false).create!(
      email_address: "pv_own@brgen.no", password: "password123", username: "pv_own", guest: false, city: @city
    )
    @stranger = User.strict_loading(false).create!(
      email_address: "pv_str@brgen.no", password: "password123", username: "pv_str", guest: false, city: @city
    )
    @playlist = Playlist::Playlist.create!(name: "Privat #{SecureRandom.hex(3)}", user: @owner, public_access: false)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a private playlist is members-only, not a 404" do
    sign_in_as(@stranger)
    host! "playlist.brgen.no"

    get playlist.playlist_path(@playlist)
    assert_response :forbidden
    assert_select "h2.empty-state-title"
  end

  test "the owner still sees a private playlist" do
    sign_in_as(@owner)
    host! "playlist.brgen.no"

    get playlist.playlist_path(@playlist)
    assert_response :success
    assert_includes response.body, @playlist.name
  end
end
