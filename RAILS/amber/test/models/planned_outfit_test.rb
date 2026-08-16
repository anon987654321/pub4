# frozen_string_literal: true

require "test_helper"

# One outfit per person per day. The uniqueness scope is `:user_id` on
# `planned_date`, which is what makes the planner a calendar rather than a list
# -- and it is also the rule that would silently stop two people planning the
# same day if the scope were ever dropped.
class PlannedOutfitTest < ActiveSupport::TestCase
  setup do
    @user = User.strict_loading(false).create!(email_address: "po@amber.test", password: "password123")
    @outfit = Outfit.create!(user: @user, name: "Rain day")
  end

  def planned(**overrides)
    PlannedOutfit.new({ user: @user, outfit: @outfit, planned_date: Date.current }.merge(overrides))
  end

  test "a plan needs a date" do
    record = planned(planned_date: nil)

    assert_not record.valid?
    assert_includes record.errors.attribute_names, :planned_date
  end

  test "a plan needs both a wearer and an outfit" do
    assert_not planned(user: nil).valid?
    assert_not planned(outfit: nil).valid?
  end

  test "one person plans one outfit per day" do
    planned.save!

    assert_not planned.valid?
  end

  test "two people may plan the same day" do
    planned.save!
    other = User.strict_loading(false).create!(email_address: "po2@amber.test", password: "password123")
    other_outfit = Outfit.create!(user: other, name: "Office")

    assert PlannedOutfit.new(user: other, outfit: other_outfit, planned_date: Date.current).valid?,
           "the uniqueness scope has lost :user_id, so one person's plan blocks everyone's"
  end

  test "one person plans as many days as they like" do
    planned.save!

    assert planned(planned_date: Date.current + 1).valid?
  end

  # --- the two calendar scopes ---------------------------------------------

  test "upcoming holds today and the future, in date order" do
    planned(planned_date: Date.current - 1).save!
    today = planned.tap(&:save!)
    later = planned(planned_date: Date.current + 3).tap(&:save!)

    assert_equal [today, later], PlannedOutfit.upcoming.to_a,
                 "today is upcoming — a plan for this morning is not history"
  end

  test "this week reaches seven days out and no further" do
    edge = planned(planned_date: Date.current + 7).tap(&:save!)
    beyond = planned(planned_date: Date.current + 8).tap(&:save!)

    assert_includes PlannedOutfit.this_week, edge
    refute_includes PlannedOutfit.this_week, beyond
  end

  test "yesterday is neither upcoming nor this week" do
    past = planned(planned_date: Date.current - 1).tap(&:save!)

    refute_includes PlannedOutfit.upcoming, past
    refute_includes PlannedOutfit.this_week, past
  end

  test "destroying an outfit takes the plans that named it" do
    planned.save!

    assert_difference "PlannedOutfit.count", -1 do
      @outfit.destroy!
    end
  end
end
