# frozen_string_literal: true

require "test_helper"

class StoryStreakTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @kari = user("streak_kari")
    @ola = user("streak_ola")
    @conversation = Conversation.find_or_create_direct(@kari, @ola)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def story_for(author)
    story = Story.new(user: author, caption: "Dagens")
    attach_pixel!(story.media, filename: "s.png")
    story.save!
    story
  end

  def reply(from:, to:, at: Time.current)
    travel_to(at) do
      Message.create!(conversation: @conversation, sender: from, content: "Svar",
                      message_type: "text", story: story_for(to))
      StoryStreak.record_exchange!(from, to, on: at.to_date)
    end
  end

  # A streak one person can hold up alone is a posting counter, not a pair still
  # talking.
  test "one direction is not a streak" do
    reply(from: @kari, to: @ola)

    assert_nil StoryStreak.for_pair(@kari, @ola)
  end

  test "both directions on the same day start it at one" do
    reply(from: @kari, to: @ola)
    reply(from: @ola, to: @kari)

    assert_equal 1, StoryStreak.for_pair(@kari, @ola).days
  end

  test "a second exchange the same day does not count twice" do
    reply(from: @kari, to: @ola)
    reply(from: @ola, to: @kari)
    reply(from: @kari, to: @ola)
    reply(from: @ola, to: @kari)

    assert_equal 1, StoryStreak.for_pair(@kari, @ola).days
  end

  test "consecutive days climb, and one missed day starts over" do
    day = Time.current.beginning_of_day + 9.hours
    reply(from: @kari, to: @ola, at: day)
    reply(from: @ola, to: @kari, at: day)
    reply(from: @kari, to: @ola, at: day + 1.day)
    reply(from: @ola, to: @kari, at: day + 1.day)

    assert_equal 2, StoryStreak.for_pair(@kari, @ola).days

    reply(from: @kari, to: @ola, at: day + 3.days)
    reply(from: @ola, to: @kari, at: day + 3.days)
    assert_equal 1, StoryStreak.for_pair(@kari, @ola).days
  end

  # Computed on read: a sweep that has not run yet would leave a dead streak on
  # the page, and the answer is one date comparison.
  test "a streak nobody kept up reads as over without a sweep" do
    streak = StoryStreak.create!(user_a: @kari, user_b: @ola, days: 7, last_day: Date.current - 3)

    assert_not streak.alive?
    assert_equal 0, streak.display_days
  end

  test "yesterday still counts as alive, because today is not over" do
    streak = StoryStreak.create!(user_a: @kari, user_b: @ola, days: 4, last_day: Date.current - 1)

    assert_predicate streak, :alive?
    assert_equal 4, streak.display_days
  end

  test "the pair is stored in id order, so either way round finds it" do
    reply(from: @kari, to: @ola)
    reply(from: @ola, to: @kari)

    assert_equal StoryStreak.for_pair(@kari, @ola).id, StoryStreak.for_pair(@ola, @kari).id
    assert_equal 1, StoryStreak.count
  end
end
