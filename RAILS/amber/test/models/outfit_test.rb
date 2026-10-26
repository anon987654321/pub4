# frozen_string_literal: true

require "test_helper"

# Asserted through the I18n key, not the English sentence. These apps default
# to nb; the literals only ever matched because rails-i18n was missing, so the
# tests were pinned to the absence of a translation.
class OutfitTest < ActiveSupport::TestCase
  setup do
    @user = User.strict_loading(false).create!(email_address: "outfit@amber.test", password: "password123")
  end

  test "requires name" do
    outfit = Outfit.new(user: @user)

    assert_not outfit.valid?
    assert_includes outfit.errors[:name], I18n.t("errors.messages.blank")
  end

  test "context_label joins season category and occasion" do
    outfit = Outfit.new(user: @user, name: "Rain day", season: "fall", category: "casual", occasion: "work")

    assert_equal "fall · casual · work", outfit.context_label
  end

  # likes_count counted presses; one person could raise it as fast as the write limit.
  test "a person likes an outfit once, however often they press" do
    outfit = Outfit.create!(user: @user, name: "Rain day")
    other = User.strict_loading(false).create!(email_address: "liker@amber.test", password: "password123")

    assert outfit.like!(other)
    refute outfit.like!(other)
    assert outfit.like!(@user)
    assert_equal 2, outfit.reload.likes_count
  end

  test "removing an outfit removes its likes" do
    outfit = Outfit.create!(user: @user, name: "Rain day")
    outfit.like!(@user)

    assert_difference -> { Reaction.count }, -1 do
      outfit.destroy!
    end
  end
end
