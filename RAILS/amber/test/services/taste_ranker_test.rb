# frozen_string_literal: true

require "test_helper"

class TasteRankerTest < ActiveSupport::TestCase
  def user(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    user.items.destroy_all
    user
  end

  test "joy and wear history outrank an untouched garment" do
    owner = user("taste-behaviour@example.com")
    loved = owner.items.create!(title: "Wool coat", category: "Outerwear", spark_joy: true, times_worn: 9, last_worn_on: Date.current - 3)
    ignored = owner.items.create!(title: "Nylon coat", category: "Outerwear", spark_joy: false, times_worn: 0)

    ranker = TasteRanker.new(owner)

    assert_operator ranker.score_for(loved), :>, ranker.score_for(ignored)
    assert_equal [ loved, ignored ], ranker.rank([ ignored, loved ])
  end

  test "an avoid preference pushes a matching garment down" do
    owner = user("taste-avoid@example.com")
    owner.style_preferences.create!(kind: :avoid, name: "polyester", weight: 1.0)
    disliked = owner.items.create!(title: "Shirt", category: "Tops", material: "polyester")
    neutral = owner.items.create!(title: "Shirt", category: "Tops", material: "linen")

    ranker = TasteRanker.new(owner)

    assert_operator ranker.score_for(disliked), :<, ranker.score_for(neutral)
    # Through the key: explain() is translated, and the suite runs under nb.
    assert_includes ranker.explain(disliked), I18n.t("taste.avoids", name: "polyester")
  end

  test "a declared aesthetic lifts a matching garment" do
    owner = user("taste-declared@example.com")
    owner.style_preferences.create!(kind: :aesthetic, name: "minimal", weight: 2.0)
    onbrand = owner.items.create!(title: "Minimal tee", category: "Tops")
    offbrand = owner.items.create!(title: "Ruffled tee", category: "Tops")

    ranker = TasteRanker.new(owner)

    assert_operator ranker.score_for(onbrand), :>, ranker.score_for(offbrand)
  end

  test "past-self garments rank below current-self garments" do
    owner = user("taste-phase@example.com")
    now = owner.items.create!(title: "Trousers", category: "Bottoms", life_phase: "current")
    then_ = owner.items.create!(title: "Trousers", category: "Bottoms", life_phase: "past-self")

    ranker = TasteRanker.new(owner)

    assert_operator ranker.score_for(now), :>, ranker.score_for(then_)
  end

  test "ordering is stable across calls" do
    owner = user("taste-stable@example.com")
    3.times { |i| owner.items.create!(title: "Tee #{i}", category: "Tops") }

    ranker = TasteRanker.new(owner)
    items = owner.items.to_a

    assert_equal ranker.rank(items).map(&:id), ranker.rank(items.shuffle).map(&:id)
  end

  test "scores stay inside 0..1" do
    owner = user("taste-bounds@example.com")
    owner.style_preferences.create!(kind: :avoid, name: "tee", weight: 99.0)
    item = owner.items.create!(title: "Tee", category: "Tops", spark_joy: false, life_phase: "past-self")

    assert_includes 0.0..1.0, TasteRanker.new(owner).score_for(item)
  end
end
