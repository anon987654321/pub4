# frozen_string_literal: true

require "test_helper"
require "shared/destroy_cascade_examples"

# ApplicationRecord sets strict_loading_by_default, and test/production both
# raise. A `dependent: :destroy` cascade has to load its dependents in order to
# delete them, and there is no preload that avoids that — so strict loading on
# such an association can only ever produce a crash, never catch an N+1 worth
# catching. Every controller `destroy` action finds its record by id, with
# nothing preloaded, which is exactly the shape that breaks.
#
# Found via Takeaway::Review (Shared::Reactable's reactions). There are 121 such
# associations across the three apps; these cover app-owned ones, and
# test_every_cascading_association_opts_out_of_strict_loading covers the rest
# by reflection.
class DestroyCascadeTest < ActiveSupport::TestCase
  # The static half: no reflection anywhere may cascade *and* strict-load.
  include Shared::DestroyCascadeExamples

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def user(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123",
      city: @city,
    )
  end

  test "destroying a community found by id takes its posts with it" do
    ActsAsTenant.with_tenant(@city) do
      author = user("cascade-author")
      community = Community.create!(name: "Cascade #{SecureRandom.hex(3)}", slug: "cascade-#{SecureRandom.hex(4)}")
      Post.create!(user: author, community:, title: "Doomed", content: "…")

      assert_difference "Post.count", -1 do
        Community.find(community.id).destroy!
      end
    end
  end

  # This case used to create an order and a review and assert the whole lot was
  # destroyed. `Marketplace::Listing#orders` is now
  # `dependent: :restrict_with_error` (operator decision 2026-08-09): an order is
  # the buyer's receipt, and the seller withdrawing a listing does not own the
  # buyer's half of it.
  #
  # Rewriting it surfaced a consequence worth stating rather than discovering
  # later. `Marketplace::Review` validates that the reviewer has an accepted or
  # completed order against the listing, so **a listing with any review
  # necessarily has an order, and can therefore never be hard-destroyed.** The
  # reviews cascade is not dead — it still fires for a listing that collected
  # favourites, deals or reviews-less traffic and never transacted, which is what
  # this case now covers — but it is unreachable for anything that ever sold.
  # That is the intended shape: a listing that has taken money is withdrawn, not
  # deleted.
  test "destroying a listing that never transacted takes its dependents with it" do
    ActsAsTenant.with_tenant(@city) do
      seller = user("cascade-seller")
      buyer = user("cascade-buyer")
      category = Marketplace::Category.find_or_create_by!(name: "Cascade", slug: "cascade-#{SecureRandom.hex(4)}")
      listing = Marketplace::Listing.create!(user: seller, category:, title: "Chair", price_cents: 4_000, currency: "NOK")
      Marketplace::ListingFavorite.create!(user: buyer, listing:)

      assert_difference "Marketplace::ListingFavorite.count", -1 do
        assert Marketplace::Listing.find(listing.id).destroy,
               "a listing with no orders is still an ordinary destroy"
      end
    end
  end

  test "a listing with orders refuses to be destroyed and keeps them" do
    ActsAsTenant.with_tenant(@city) do
      seller = user("restrict-seller")
      buyer = user("restrict-buyer")
      category = Marketplace::Category.find_or_create_by!(name: "Restrict", slug: "restrict-#{SecureRandom.hex(4)}")
      listing = Marketplace::Listing.create!(user: seller, category:, title: "Desk", price_cents: 9_000, currency: "NOK")
      Marketplace::Order.create!(buyer:, listing:, status: "accepted")

      found = Marketplace::Listing.find(listing.id)

      assert_no_difference [ "Marketplace::Order.count", "Marketplace::Listing.count" ] do
        refute found.destroy, "a listing with orders must refuse to be destroyed"
      end
      assert_predicate found.errors[:base], :any?,
                       "restrict_with_error must say why, not fail silently"
      assert_predicate Marketplace::Listing.where(id: listing.id), :exists?
    end
  end

  # The normal path is withdrawal, not deletion, and it must not touch orders.
  test "withdrawing a listing keeps its orders and hides it from the index" do
    ActsAsTenant.with_tenant(@city) do
      seller = user("withdraw-seller")
      buyer = user("withdraw-buyer")
      category = Marketplace::Category.find_or_create_by!(name: "Withdraw", slug: "withdraw-#{SecureRandom.hex(4)}")
      listing = Marketplace::Listing.create!(user: seller, category:, title: "Lamp", price_cents: 2_500, currency: "NOK")
      Marketplace::Order.create!(buyer:, listing:, status: "accepted")

      assert_no_difference "Marketplace::Order.count" do
        Marketplace::Listing.find(listing.id).update!(status: "removed")
      end
      refute_includes Marketplace::Listing.active.pluck(:id), listing.id,
                      "a withdrawn listing must leave the active scope the index resolves through"
    end
  end
end
