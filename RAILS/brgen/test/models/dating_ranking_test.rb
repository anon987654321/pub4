# frozen_string_literal: true

require "test_helper"

# The deck was ORDER BY RANDOM(). Orientation, neighbourhood and a 20 km radius
# filtered the pool and nothing ranked it, so someone last seen in March sat
# beside someone online now — and every reload reshuffled, so a profile you had
# just passed could not be found again.
class DatingRankingTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @viewer = User.strict_loading(false).create!(
      email_address: "dr_viewer@brgen.no", password: "password123", username: "dr_viewer", city: @city
    )
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def profile(handle:, last_active: nil, prompts: 0)
    user = User.strict_loading(false).create!(
      email_address: "dr_#{handle}@brgen.no", password: "password123", username: "dr_#{handle}", city: @city
    )
    p = Dating::Profile.new(user: user, age: 30, bio: "hei", visible: true, last_active_at: last_active)
    attach_pixel!(p.photos)
    p.save!
    prompts.times do |i|
      Dating::Prompt.create!(profile: p, question: Dating::Prompt::QUESTIONS[i], answer: "svar #{i}", position: i)
    end
    p
  end

  test "someone active this week outranks someone last seen in March" do
    dormant = profile(handle: "dormant", last_active: 120.days.ago)
    recent = profile(handle: "recent", last_active: 1.hour.ago)

    ranked = Dating::Profile.visible.ranked_for(@viewer).map(&:id)
    assert_operator ranked.index(recent.id), :<, ranked.index(dormant.id)
  end

  test "a never-seen profile ranks below a dormant one, not above" do
    never = profile(handle: "never")
    dormant = profile(handle: "dormant2", last_active: 120.days.ago)

    ranked = Dating::Profile.visible.ranked_for(@viewer).map(&:id)
    assert_operator ranked.index(dormant.id), :<, ranked.index(never.id)
  end

  # A profile with prompts gives the viewer something to reply to, which is the
  # whole interaction this vertical is for.
  test "among equally recent profiles, answered prompts come first" do
    bare = profile(handle: "bare", last_active: 1.hour.ago)
    answered = profile(handle: "answered", last_active: 1.hour.ago, prompts: 2)

    ranked = Dating::Profile.visible.ranked_for(@viewer).map(&:id)
    assert_operator ranked.index(answered.id), :<, ranked.index(bare.id)
  end

  # Stability is the point of not using RANDOM(): a profile you just passed has
  # to still be findable on the next page load.
  test "the order is stable for one viewer on one day" do
    4.times { |i| profile(handle: "stable#{i}", last_active: 1.hour.ago) }

    first = Dating::Profile.visible.ranked_for(@viewer).map(&:id)
    second = Dating::Profile.visible.ranked_for(@viewer).map(&:id)
    assert_equal first, second
  end

  # And without a per-viewer salt the same profile is top of everyone's deck
  # forever.
  test "two viewers do not get an identical deck" do
    8.times { |i| profile(handle: "spread#{i}", last_active: 1.hour.ago) }
    other = User.strict_loading(false).create!(
      email_address: "dr_other@brgen.no", password: "password123", username: "dr_other", city: @city
    )

    mine = Dating::Profile.visible.ranked_for(@viewer).map(&:id)
    theirs = Dating::Profile.visible.ranked_for(other).map(&:id)
    refute_equal mine, theirs
  end

  test "touch_activity! records being around without pretending a photo job was" do
    p = profile(handle: "active")
    assert_nil p.last_active_at

    p.touch_activity!
    assert_not_nil p.reload.last_active_at
  end

  test "a profile answers at most three prompts" do
    p = profile(handle: "chatty", prompts: 3)

    fourth = Dating::Prompt.new(profile: p, question: Dating::Prompt::QUESTIONS[3], answer: "for mye")
    refute fourth.valid?, "a profile answering eight is a bio in disguise"
  end

  test "a prompt question must be one of the fixed list" do
    p = profile(handle: "freeform")

    refute Dating::Prompt.new(profile: p, question: "Whatever I like", answer: "x").valid?
  end
end
