# frozen_string_literal: true

require "test_helper"

class Playlist::CollaborationTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = create_user("collab_owner")
    @guest = create_user("collab_guest")
    @set = Playlist::Set.create!(name: "Lørdagssett", user: @owner)
    @other_set = Playlist::Set.create!(name: "Søndagssett", user: @owner)
  end

  # The column defaults to editor too; a form submitting an empty select is the
  # case only the callback answers.
  test "a collaborator given a blank role is an editor" do
    assert_equal "editor", Playlist::Collaboration.create!(user: @guest, set: @set, role: "").role
  end

  test "the role is one of the three known roles" do
    collaboration = Playlist::Collaboration.new(user: @guest, set: @set, role: "admin")

    assert_not collaboration.valid?
    assert collaboration.errors.added?(:role, :inclusion, value: "admin")
  end

  test "a person collaborates on a set once, and on another set freely" do
    Playlist::Collaboration.create!(user: @guest, set: @set)
    again = Playlist::Collaboration.new(user: @guest, set: @set, role: "viewer")

    assert_not again.valid?
    assert again.errors.added?(:user_id, :taken, value: @guest.id)
    assert Playlist::Collaboration.new(user: @guest, set: @other_set).valid?
  end

  private

  def create_user(name)
    User.strict_loading(false).create!(email_address: "#{name}@brgen.no", password: "password123", city: @city)
  end
end
