# frozen_string_literal: true

require "test_helper"

class Dating::DislikeTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @viewer = User.strict_loading(false).create!(email_address: "dislike_a@brgen.no", password: "password123", city: @city)
    @other = User.strict_loading(false).create!(email_address: "dislike_b@brgen.no", password: "password123", city: @city)
    @third = User.strict_loading(false).create!(email_address: "dislike_c@brgen.no", password: "password123", city: @city)
  end

  test "passing on the same person twice is refused" do
    Dating::Dislike.create!(disliker: @viewer, dislikee: @other)
    duplicate = Dating::Dislike.new(disliker: @viewer, dislikee: @other)

    assert_not duplicate.valid?
    assert duplicate.errors.added?(:disliker_id, :taken, value: @viewer.id)
  end

  test "two people may each pass on the other" do
    Dating::Dislike.create!(disliker: @viewer, dislikee: @other)

    assert Dating::Dislike.new(disliker: @other, dislikee: @viewer).valid?
  end

  test "nobody can pass on themselves" do
    dislike = Dating::Dislike.new(disliker: @viewer, dislikee: @viewer)

    assert_not dislike.valid?
    assert dislike.errors.added?(:dislikee, :self_dislike)
  end

  test "rewind undoes only the most recent pass, and only the viewer's" do
    older = Dating::Dislike.create!(disliker: @viewer, dislikee: @other, created_at: 2.minutes.ago)
    newest = Dating::Dislike.create!(disliker: @viewer, dislikee: @third, created_at: 1.minute.ago)
    theirs = Dating::Dislike.create!(disliker: @other, dislikee: @viewer)

    Dating::Dislike.rewind!(@viewer)

    assert Dating::Dislike.exists?(older.id)
    assert_not Dating::Dislike.exists?(newest.id)
    assert Dating::Dislike.exists?(theirs.id)
  end

  test "rewind with nothing to undo returns nil" do
    assert_nil Dating::Dislike.rewind!(@viewer)
  end
end
