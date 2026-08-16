# frozen_string_literal: true

require "test_helper"

# The join between an outfit and the garments in it. Two things here are easy to
# get wrong and neither was covered: the uniqueness scope, which is what stops
# the same shirt appearing twice in one outfit while still allowing it in every
# other outfit, and the default_scope on :position, which is the only reason an
# outfit renders in the order someone arranged it.
class OutfitItemTest < ActiveSupport::TestCase
  setup do
    @user = User.strict_loading(false).create!(email_address: "oi@amber.test", password: "password123")
    @outfit = Outfit.create!(user: @user, name: "Rain day")
    @shirt = Item.create!(user: @user, title: "Oxford", category: "Tops")
    @coat = Item.create!(user: @user, title: "Wool coat", category: "Outerwear")
  end

  test "both ends are required" do
    assert_not OutfitItem.new(outfit: @outfit).valid?
    assert_not OutfitItem.new(item: @shirt).valid?
    assert OutfitItem.new(outfit: @outfit, item: @shirt).valid?
  end

  test "a garment appears once in an outfit" do
    OutfitItem.create!(outfit: @outfit, item: @shirt)

    assert_not OutfitItem.new(outfit: @outfit, item: @shirt).valid?
  end

  test "the same garment belongs in as many outfits as you like" do
    OutfitItem.create!(outfit: @outfit, item: @shirt)
    other = Outfit.create!(user: @user, name: "Office")

    assert OutfitItem.new(outfit: other, item: @shirt).valid?,
           "a shirt used in one outfit cannot be used in another"
  end

  test "an outfit holds more than one garment" do
    OutfitItem.create!(outfit: @outfit, item: @shirt)

    assert OutfitItem.new(outfit: @outfit, item: @coat).valid?
  end

  # The default scope is the whole of the ordering contract. Without it an
  # outfit renders in insertion order, which is not the order anyone arranged.
  test "entries come back in the order they were arranged, not the order they were added" do
    last = OutfitItem.create!(outfit: @outfit, item: @coat, position: 2)
    first = OutfitItem.create!(outfit: @outfit, item: @shirt, position: 1)

    assert_equal [first, last], OutfitItem.where(outfit: @outfit).to_a
  end

  test "reordering moves the render order" do
    coat = OutfitItem.create!(outfit: @outfit, item: @coat, position: 1)
    shirt = OutfitItem.create!(outfit: @outfit, item: @shirt, position: 2)

    assert_equal [coat, shirt], OutfitItem.where(outfit: @outfit).to_a

    coat.update!(position: 3)
    assert_equal [shirt, coat], OutfitItem.where(outfit: @outfit).to_a
  end

  test "an unpositioned entry does not break the ordering" do
    OutfitItem.create!(outfit: @outfit, item: @shirt)
    OutfitItem.create!(outfit: @outfit, item: @coat, position: 1)

    assert_equal 2, OutfitItem.where(outfit: @outfit).count
  end

  test "destroying an outfit clears its entries and leaves the garments" do
    OutfitItem.create!(outfit: @outfit, item: @shirt)

    assert_difference "OutfitItem.count", -1 do
      assert_no_difference "Item.count" do
        @outfit.destroy!
      end
    end
  end

  test "destroying a garment removes it from the outfits it was in" do
    OutfitItem.create!(outfit: @outfit, item: @shirt)

    assert_difference "OutfitItem.count", -1 do
      @shirt.destroy!
    end
    assert Outfit.exists?(@outfit.id), "losing a garment deleted the whole outfit"
  end
end
