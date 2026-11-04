# frozen_string_literal: true

require "test_helper"

# Three forms that offered the wrong thing: the declutter page's Review link
# stood beside each card as a grid cell of its own; the showcase select
# offered garments already on the showcase; and a live session's time field
# took any past moment and started empty.
class DeclutterShowcaseScheduleTest < ActionDispatch::IntegrationTest
  setup do
    email = "forms-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
  end

  test "the declutter box's Review link is inside each card" do
    item = @user.items.create!(title: "Wool coat", category: "Outerwear", lifecycle_state: "declutter_box",
                               times_worn: 0)

    get declutter_index_path
    assert_select ".items-grid > a[href=?]", review_declutter_path(item), 0
    assert_select ".items-grid article##{ActionView::RecordIdentifier.dom_id(item)} nav a[href=?]",
                  review_declutter_path(item)
  end

  test "the showcase select offers only garments not yet on the showcase" do
    shown = @user.items.create!(title: "Blazer", category: "Outerwear")
    spare = @user.items.create!(title: "Scarf", category: "Accessories")
    profile = @user.create_creator_profile!(handle: "cr#{SecureRandom.hex(3)}", display_name: "Creator")
    profile.creator_wardrobe_items.create!(item: shown)

    get edit_my_creator_profile_path
    assert_response :success
    assert_select "select[name=item_id] option[value=?]", spare.id.to_s
    assert_select "select[name=item_id] option[value=?]", shown.id.to_s, 0
  end

  test "a session is scheduled from the next full hour, never in the past" do
    travel_to Time.zone.local(2026, 11, 20, 18, 12, 30) do
      get live_streams_path
      field = css_select("input[type=datetime-local][name='live_stream[scheduled_at]']").first
      assert field, "no schedule field"
      assert_match(/\A2026-11-20T19:00/, field["value"].to_s)
      assert_match(/\A2026-11-20T18:12/, field["min"].to_s)
    end
  end
end
