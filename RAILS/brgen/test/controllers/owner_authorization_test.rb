# frozen_string_literal: true

require "test_helper"

# Ownership checks that read a belongs_to off a record found by id.
#
# ApplicationRecord sets strict_loading_by_default = true in every environment,
# production raising rather than logging. So this shape:
#
#   @community = Community.find(params[:id])   # set_community
#   ...
#   return if Current.user == @community.user  # authorize_owner
#
# raises StrictLoadingViolationError before the comparison happens. The guard
# does not deny access — it never runs. Every path behind it, including the
# owner's own, fails.
#
# Four controllers had it: communities, playlist/sets, playlist/dilla_sketches
# and takeaway/delivery_drivers, all found the same day as the comments one and
# all fixed by comparing the foreign key instead. This pins the brgen host case;
# the engine ones share the fix and the shape.
class OwnerAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def user(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", city: @city,
    )
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def community_owned_by(owner)
    Community.create!(name: "Own #{SecureRandom.hex(3)}", slug: "own-#{SecureRandom.hex(4)}", user: owner)
  end

  test "the owner reaches the edit form for their own community" do
    ActsAsTenant.with_tenant(@city) do
      owner = user("owner")
      community = community_owned_by(owner)
      sign_in(owner)

      # Before the fix this raised StrictLoadingViolationError rather than
      # rendering — the owner was locked out of their own community by a guard
      # that never got as far as comparing anything.
      get edit_community_path(community)

      assert_response :success
    end
  end

  test "a stranger is turned away from someone else's community" do
    ActsAsTenant.with_tenant(@city) do
      owner = user("owner")
      stranger = user("stranger")
      community = community_owned_by(owner)
      sign_in(stranger)

      get edit_community_path(community)

      assert_redirected_to community_path(community)
    end
  end

  test "a stranger cannot update someone else's community" do
    ActsAsTenant.with_tenant(@city) do
      owner = user("owner")
      stranger = user("stranger")
      community = community_owned_by(owner)
      original = community.name
      sign_in(stranger)

      patch community_path(community), params: { community: { name: "Seized" } }

      assert_equal original, community.reload.name,
                   "only the owner may rename a community"
    end
  end

  test "the owner can update their own community" do
    ActsAsTenant.with_tenant(@city) do
      owner = user("owner")
      community = community_owned_by(owner)
      sign_in(owner)

      patch community_path(community), params: { community: { name: "Renamed by owner" } }

      assert_equal "Renamed by owner", community.reload.name
    end
  end
end
