# frozen_string_literal: true

require "test_helper"

class Dating::ProfileTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(
      email_address: "date_#{SecureRandom.hex(3)}@brgen.no",
      password: "password123",
      city: @city
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a visible profile cannot be created without photos" do
    ActsAsTenant.with_tenant(@city) do
      profile = Dating::Profile.new(user: @user, age: 28, visible: true)

      assert_not profile.valid?
      assert profile.errors[:photos].any?
    end
  end

  test "a hidden profile can be created without photos" do
    ActsAsTenant.with_tenant(@city) do
      profile = Dating::Profile.new(user: @user, age: 28, visible: false)

      assert profile.valid?
    end
  end

  test "a removed neighborhood leaves the profile standing without one" do
    ActsAsTenant.with_tenant(@city) do
      neighborhood = Neighborhood.create!(city: @city, name: "Sandviken", slug: "sandviken-#{SecureRandom.hex(3)}")
      profile = Dating::Profile.create!(user: @user, age: 28, visible: false, neighborhood:)

      neighborhood.destroy!

      assert Dating::Profile.exists?(profile.id)
      assert_nil Dating::Profile.where(id: profile.id).pick(:neighborhood_id)
    end
  end
end
