# frozen_string_literal: true

require "test_helper"

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

  test "destroying a marketplace listing found by id takes its reviews with it" do
    ActsAsTenant.with_tenant(@city) do
      seller = user("cascade-seller")
      buyer = user("cascade-buyer")
      category = Marketplace::Category.find_or_create_by!(name: "Cascade", slug: "cascade-#{SecureRandom.hex(4)}")
      listing = Marketplace::Listing.create!(user: seller, category:, title: "Chair", price_cents: 4_000, currency: "NOK")
      Marketplace::Order.create!(buyer:, listing:, status: "accepted")
      Marketplace::Review.create!(user: buyer, listing:, rating: 4)

      assert_difference "Marketplace::Review.count", -1 do
        Marketplace::Listing.find(listing.id).destroy!
      end
    end
  end

  # The static half: no reflection anywhere may cascade *and* strict-load.
  test "every cascading association opts out of strict loading" do
    Rails.application.eager_load!
    cascading = %i[destroy destroy_async delete_all].freeze

    offenders = ApplicationRecord.descendants.flat_map do |model|
      next [] if model.abstract_class?

      model.reflect_on_all_associations.filter_map do |reflection|
        next unless cascading.include?(reflection.options[:dependent])
        next if reflection.options[:strict_loading] == false

        "#{model.name}##{reflection.name}"
      end
    end

    assert_empty offenders.sort,
                 "these cascade on destroy but strict-load, so destroy-by-id raises"
  end
end
