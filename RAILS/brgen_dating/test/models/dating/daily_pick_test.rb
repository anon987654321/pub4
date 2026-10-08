# frozen_string_literal: true

require "test_helper"

class Dating::DailyPickTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @viewer = User.strict_loading(false).create!(email_address: "picks_viewer@brgen.no", password: "password123", city: @city)
    @profiles = ActsAsTenant.with_tenant(@city) do
      Array.new(7) do |index|
        user = User.strict_loading(false).create!(email_address: "picks_#{index}@brgen.no", password: "password123", city: @city)
        Dating::Profile.create!(user: user, age: 25 + index, visible: false)
      end
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "today's list holds at most PER_DAY profiles and is the same list all day" do
    ActsAsTenant.with_tenant(@city) do
      first = Dating::DailyPick.for_today(@viewer, scope: pool)
      again = Dating::DailyPick.for_today(@viewer, scope: pool)

      assert_equal Dating::DailyPick::PER_DAY, first.size
      assert_equal first.map(&:id).sort, again.map(&:id).sort
      assert_equal Dating::DailyPick::PER_DAY, Dating::DailyPick.for_day.where(user_id: @viewer.id).count
    end
  end

  test "a profile picked this week is not picked again tomorrow" do
    ActsAsTenant.with_tenant(@city) do
      today = Dating::DailyPick.for_today(@viewer, scope: pool).map(&:id)
      tomorrow = Dating::DailyPick.for_today(@viewer, scope: pool, day: Date.current + 1).map(&:id)

      assert_empty today & tomorrow
      assert_equal @profiles.size - Dating::DailyPick::PER_DAY, tomorrow.size
    end
  end

  # The database key, not a validation, holds one row per (user, profile, day);
  # for_today leans on RecordNotUnique to settle two tabs drawing at once.
  test "the same pick twice in one day is refused by the database" do
    Dating::DailyPick.create!(user: @viewer, profile: @profiles.first, picked_on: Date.current)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Dating::DailyPick.create!(user: @viewer, profile: @profiles.first, picked_on: Date.current)
    end
  end

  private

  def pool = Dating::Profile.where(id: @profiles.map(&:id)).order(:id)
end
