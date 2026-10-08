# frozen_string_literal: true

require "test_helper"

class Playlist::LikeTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = create_user("like_owner")
    @fan = create_user("like_fan")
    @set = Playlist::Set.create!(name: "Kveldssett", user: @owner)
  end

  test "a like must point at a set or a playlist" do
    like = Playlist::Like.new(user: @fan)

    assert_not like.valid?
    assert like.errors.added?(:base, :target_required)
  end

  test "a person likes a set once" do
    Playlist::Like.create!(user: @fan, set: @set)
    again = Playlist::Like.new(user: @fan, set: @set)

    assert_not again.valid?
    assert again.errors.added?(:user_id, :taken, value: @fan.id)
    assert Playlist::Like.new(user: @owner, set: @set).valid?
  end

  private

  def create_user(name)
    User.strict_loading(false).create!(email_address: "#{name}@brgen.no", password: "password123", city: @city)
  end
end
