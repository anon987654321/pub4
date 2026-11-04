# frozen_string_literal: true

require "test_helper"

# The category select hid the cards already loaded, so every page infinite
# scroll appended came in unfiltered; the analytics chips counted garments
# without opening them; the counters summed the loaded page and changed as it
# grew; and the seasonal moves neither counted what they moved nor asked first.
class WardrobeFiltersTest < ActionDispatch::IntegrationTest
  setup do
    email = "filters-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    @coat = @user.items.create!(title: "Wool coat", category: "Outerwear", times_worn: 0)
    @shirt = @user.items.create!(title: "Linen shirt", category: "Tops", times_worn: 7, spark_joy: true)
  end

  def reflex_scope(dataset)
    reflex = ItemsInfiniteScrollReflex.allocate
    reflex.define_singleton_method(:element) { Struct.new(:dataset).new(dataset) }
    Current.set(user: @user) { reflex.send(:scope).to_a }
  end

  test "the category filter is applied by the server, on later pages too" do
    get items_path(category: "Tops")
    assert_select "#items article.item-card", 1
    assert_select "#items article##{ActionView::RecordIdentifier.dom_id(@shirt)}"
    assert_select "form[action=?][method=get] select[name=category] option[selected][value=Tops]", items_path

    assert_equal [ @shirt ], reflex_scope("lifecycle" => "active", "category" => "Tops")
  end

  test "the analytics chips open the garments they count" do
    get items_path
    assert_select "a.chip[href=?]", items_path(lifecycle: "all", usage: "never_worn")
    assert_select "a.chip[href=?]", items_path(lifecycle: "box")

    get items_path(lifecycle: "all", usage: "never_worn")
    assert_select "#items article.item-card", 1
    assert_select "#items article##{ActionView::RecordIdentifier.dom_id(@coat)}"
    assert_equal [ @coat ], reflex_scope("lifecycle" => "all", "usage" => "never_worn")
  end

  test "the counters count the whole filtered wardrobe" do
    get items_path
    assert_select ".tag", text: I18n.t("items.wears_total", count: 7)
    assert_select ".tag", text: I18n.t("items.joy_keepers", count: 1)
    assert_select ".tag", text: I18n.t("items.categories", count: 2)
  end

  test "the seasonal moves say how many garments moved, and archiving asks first" do
    get items_path
    question = I18n.t("items.confirm_archive_seasonal")
    assert_select "form[action=?][data-turbo-confirm=?]", archive_seasonal_items_path, question

    post archive_seasonal_items_path
    assert_equal I18n.t("flash.out_of_season_archived", count: 0), flash[:notice]
  end
end
