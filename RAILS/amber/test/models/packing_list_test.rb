# frozen_string_literal: true

require "test_helper"

# A packing list is a date range and a set of garments, and the only arithmetic
# it does is duration_days -- which is inclusive, because a trip that leaves and
# returns on the same day is one day of packing and not zero.
class PackingListTest < ActiveSupport::TestCase
  setup do
    @user = User.strict_loading(false).create!(email_address: "pack@amber.test", password: "password123")
  end

  def list(**overrides)
    PackingList.new({ user: @user, name: "Oslo", starts_on: Date.new(2026, 8, 16),
                      ends_on: Date.new(2026, 8, 20) }.merge(overrides))
  end

  test "a list needs a name and both ends of its range" do
    blank = PackingList.new(user: @user)

    assert_not blank.valid?
    %i[name starts_on ends_on].each { |field| assert_includes blank.errors.attribute_names, field }
  end

  test "a list belongs to somebody" do
    assert_not list(user: nil).valid?
  end

  test "a trip cannot end before it starts" do
    backwards = list(starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 8, 16))

    assert_not backwards.valid?
    assert_includes backwards.errors.attribute_names, :ends_on
  end

  test "a trip may start and end on the same day" do
    same_day = list(ends_on: Date.new(2026, 8, 16))

    assert same_day.valid?
  end

  # Inclusive. A trip that leaves and returns on one day is one day of packing.
  test "duration counts both the first day and the last" do
    assert_equal 5, list.duration_days
    assert_equal 1, list(ends_on: Date.new(2026, 8, 16)).duration_days
  end

  test "duration is zero rather than nil when the range is incomplete" do
    assert_equal 0, list(starts_on: nil).duration_days
    assert_equal 0, list(ends_on: nil).duration_days
    assert_equal 0, PackingList.new.duration_days
  end

  test "a list crossing a month boundary counts the days and not the dates" do
    assert_equal 4, list(starts_on: Date.new(2026, 8, 30), ends_on: Date.new(2026, 9, 2)).duration_days
  end

  # --- what goes in it ------------------------------------------------------

  test "items reach the list through its entries" do
    record = list.tap(&:save!)
    item = Item.create!(user: @user, title: "Rain shell", category: "Outerwear")
    PackingListItem.create!(packing_list: record, item:)

    assert_equal [item], PackingList.where(id: record.id).includes(:items).first.items.to_a
  end

  test "destroying a list takes its entries and leaves the garments" do
    record = list.tap(&:save!)
    item = Item.create!(user: @user, title: "Rain shell", category: "Outerwear")
    PackingListItem.create!(packing_list: record, item:)

    assert_difference "PackingListItem.count", -1 do
      assert_no_difference "Item.count" do
        record.destroy!
      end
    end
  end

  test "the same garment can be on two trips" do
    first = list.tap(&:save!)
    second = list(name: "Bergen", starts_on: Date.new(2026, 9, 1), ends_on: Date.new(2026, 9, 3)).tap(&:save!)
    item = Item.create!(user: @user, title: "Rain shell", category: "Outerwear")

    PackingListItem.create!(packing_list: first, item:)

    assert PackingListItem.new(packing_list: second, item:).valid?,
           "a garment packed for one trip cannot be packed for another"
  end
end
