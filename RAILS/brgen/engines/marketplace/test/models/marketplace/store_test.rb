# frozen_string_literal: true

require "test_helper"

class Marketplace::StoreTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "store_owner@brgen.no", password: "password123", city: @city
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a shop without a slug takes one from its name and routes by it" do
    ActsAsTenant.with_tenant(@city) do
      store = Marketplace::Store.create!(owner: @owner, name: "Fisketorget Delikatesse")

      assert_equal "fisketorget-delikatesse", store.slug
      assert_equal store.slug, store.to_param
    end
  end

  test "two shops cannot share a slug" do
    ActsAsTenant.with_tenant(@city) do
      Marketplace::Store.create!(owner: @owner, name: "Første", slug: "samme")
      second = Marketplace::Store.new(owner: @owner, name: "Andre", slug: "samme")

      assert_not second.valid?
      assert second.errors.added?(:slug, :taken, value: "samme")
    end
  end

  test "a shop needs a name, a known vertical and a Stripe account id of the right shape" do
    ActsAsTenant.with_tenant(@city) do
      store = Marketplace::Store.new(owner: @owner, name: "", vertical: "weapons", stripe_connect_id: "not-an-account")

      assert_not store.valid?
      assert store.errors.added?(:name, :blank)
      assert store.errors.added?(:slug, :blank)
      assert store.errors.added?(:vertical, :inclusion, value: "weapons")
      assert store.errors.added?(:stripe_connect_id, :invalid, value: "not-an-account")
      assert Marketplace::Store.new(owner: @owner, name: "Butikk", stripe_connect_id: "acct_1AbC").valid?
    end
  end

  test "grocery is the groceries vertical and nothing else" do
    assert Marketplace::Store.new(vertical: "groceries").grocery?
    assert_not Marketplace::Store.new(vertical: "homewares").grocery?
  end

  test "active and by_vertical narrow the shop list" do
    ActsAsTenant.with_tenant(@city) do
      open = Marketplace::Store.create!(owner: @owner, name: "Åpen", vertical: "books", active: true)
      closed = Marketplace::Store.create!(owner: @owner, name: "Stengt", vertical: "books", active: false)
      pets = Marketplace::Store.create!(owner: @owner, name: "Dyr", vertical: "pets", active: true)

      assert_includes Marketplace::Store.active, open
      assert_not_includes Marketplace::Store.active, closed
      assert_equal [ open, closed ].map(&:id).sort, Marketplace::Store.by_vertical("books").pluck(:id).sort
      assert_includes Marketplace::Store.by_vertical(""), pets
    end
  end
end
