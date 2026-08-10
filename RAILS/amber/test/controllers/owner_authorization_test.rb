# frozen_string_literal: true

require "test_helper"

# Ownership guards that read a belongs_to off a record found by id.
#
# ApplicationRecord sets strict_loading_by_default = true in every environment,
# production raising rather than logging, so:
#
#   @wardrobe_item = WardrobeItem.find(params[:id])   # set_wardrobe_item
#   ...
#   unless @wardrobe_item.user == Current.user        # authorize!
#
# raises StrictLoadingViolationError before the comparison. The guard does not
# deny access — it never runs, and every path behind it fails, including the
# owner's own.
#
# Seven controllers across brgen and amber had this shape, all found on
# 2026-08-10. These two are amber's; the brgen five are pinned in
# brgen/test/controllers/{comment_ownership,owner_authorization}_test.rb.
class OwnerAuthorizationTest < ActionDispatch::IntegrationTest
  def user(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@amber.test",
      password: "password123",
    )
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def item_for(owner)
    item = Item.create!(user: owner, title: "Coat #{SecureRandom.hex(3)}", category: "Outerwear")
    WardrobeItem.create!(user: owner, item: item)
  end

  test "the owner reaches their own wardrobe item" do
    owner = user("owner")
    wardrobe_item = item_for(owner)
    sign_in(owner)

    # Before the fix this raised rather than rendering: the owner was locked out
    # of their own item by a guard that never compared anything.
    get wardrobe_item_path(wardrobe_item)

    assert_response :success
  end

  test "a stranger is turned away from someone else's wardrobe item" do
    owner = user("owner")
    stranger = user("stranger")
    wardrobe_item = item_for(owner)
    sign_in(stranger)

    get wardrobe_item_path(wardrobe_item)

    assert_redirected_to wardrobe_items_path
  end

  test "a stranger cannot destroy someone else's wardrobe item" do
    owner = user("owner")
    stranger = user("stranger")
    wardrobe_item = item_for(owner)
    sign_in(stranger)

    assert_no_difference "WardrobeItem.count" do
      delete wardrobe_item_path(wardrobe_item)
    end
  end

  test "the owner can destroy their own wardrobe item" do
    owner = user("owner")
    wardrobe_item = item_for(owner)
    sign_in(owner)

    assert_difference "WardrobeItem.count", -1 do
      delete wardrobe_item_path(wardrobe_item)
    end
  end
end
