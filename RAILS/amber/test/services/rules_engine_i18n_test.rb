# frozen_string_literal: true

require "test_helper"

# The rules engines used to emit English prose under translated headings, so a
# Norwegian page read half in each language. These assert the copy actually
# follows the locale rather than merely existing in both files.
class RulesEngineI18nTest < ActiveSupport::TestCase
  def user(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    user.items.destroy_all
    user
  end

  test "closet organization speaks the reader's language" do
    owner = user("i18n-closet@example.com")
    owner.items.create!(title: "Torn coat", category: "Outerwear", lifecycle_state: "repair", material: "wool")

    nb = I18n.with_locale(:nb) { ClosetOrganization.new(owner).tips }
    en = I18n.with_locale(:en) { ClosetOrganization.new(owner).tips }

    assert_equal nb.map(&:id), en.map(&:id), "the rules themselves must not depend on locale"
    assert_not_equal nb.map(&:title), en.map(&:title)
    assert_includes en.map(&:principle), "Kintsugi — mend visibly rather than discard"
    assert_includes nb.map(&:principle), "Kintsugi — lapp synlig framfor å kaste"
  end

  test "every closet tip resolves in both locales" do
    owner = user("i18n-closet-all@example.com")
    owner.items.create!(title: "Dirty", category: "Tops", lifecycle_state: "clean_needed")
    owner.items.create!(title: "Torn", category: "Tops", lifecycle_state: "repair")
    owner.items.create!(title: "Short", category: "Bottoms", lifecycle_state: "tailor")
    owner.items.create!(title: "Jumper", category: "Tops", material: "merino wool", times_worn: 9)
    owner.items.create!(title: "Blouse", category: "Tops", material: "silk", color: "ivory")
    owner.items.create!(title: "Jeans", category: "Bottoms", material: "denim", color: "indigo")
    owner.items.create!(title: "Boots", category: "Shoes", material: "leather", color: "brown")
    owner.items.create!(title: "Tee", category: "Tops", material: "cotton", color: "white")
    owner.items.create!(title: "Scarf", category: "Accessories", color: "cream")

    I18n.available_locales.each do |locale|
      tips = I18n.with_locale(locale) { ClosetOrganization.new(owner).tips }

      assert_operator tips.size, :>, 4, "#{locale} produced almost no tips"
      tips.each do |tip|
        [ tip.title, tip.body, tip.principle ].each do |text|
          assert_no_match(/translation missing/i, text, "#{tip.id} in #{locale}")
          assert_no_match(/%\{/, text, "#{tip.id} in #{locale} left an interpolation unfilled")
        end
      end
    end
  end

  test "taste explanations, coach tips, gaps and duplicates all follow the locale" do
    owner = user("i18n-rest@example.com")
    owner.style_preferences.create!(kind: :avoid, name: "polyester", weight: 1.0)
    disliked = owner.items.create!(title: "Shirt", category: "Tops", material: "polyester", times_worn: 4)
    2.times { |i| owner.items.create!(title: "White tee #{i}", category: "Tops", color: "white", material: "cotton", brand: "Cos") }

    I18n.available_locales.each do |locale|
      I18n.with_locale(locale) do
        assert_no_match(/translation missing/i, TasteRanker.new(owner).explain(disliked).join(" "))
        assert_no_match(/translation missing/i, WardrobeAnalytics.new(owner).summary[:tips].join(" "))
        assert_no_match(/translation missing/i, WardrobeGap.new(owner).gaps.map { |gap| gap[:reason] }.join(" "))
        assert_no_match(/translation missing/i, DuplicateDetector.new(owner).ranked_groups.map { |group| group[:reason] }.join(" "))
      end
    end

    nb = I18n.with_locale(:nb) { TasteRanker.new(owner).explain(disliked) }
    en = I18n.with_locale(:en) { TasteRanker.new(owner).explain(disliked) }
    assert_not_equal nb, en
  end

  test "a duplicate reason reads cleanly when the garments have no colour" do
    owner = user("i18n-duplicates-nocolor@example.com")
    2.times { |i| owner.items.create!(title: "Tee #{i}", category: "Tops", material: "cotton") }

    reason = DuplicateDetector.new(owner).ranked_groups.first[:reason]

    assert_no_match(/\s{2,}/, reason, "a blank colour left a double space")
  end
end
