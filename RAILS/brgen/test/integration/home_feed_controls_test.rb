# frozen_string_literal: true

require "test_helper"

# The controls around the front-page feed: the neighbourhood filter, the
# follow hint a signed-out reader sees, the search hit count and the empty
# state a neighbourhood with no posts gets.
class HomeFeedControlsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @neighborhood = Neighborhood.create!(city: @city, name: "Sandviken #{SecureRandom.hex(2)}",
                                         slug: "sandviken-#{SecureRandom.hex(3)}")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def page = Nokogiri::HTML(response.body)

  test "choosing a neighbourhood applies it, and Apply waits in noscript" do
    get root_path

    form = page.at_css("form.home-neighborhood-filter")
    assert_equal "auto-submit", form["data-controller"]
    assert_equal "change->auto-submit#submit", form.at_css("select#home-neighborhood")["data-action"]
    assert_nil form.at_css("> button[type=submit]"), "Apply is still a visible step for a reader with JavaScript"
    assert_includes form.at_css("noscript").inner_html, I18n.t("actions.apply")
  end

  test "the follow hint is one translated sentence around its link" do
    get root_path(feed: "following")

    hint = page.at_css("p.feed-hint")
    refute_nil hint
    link = hint.at_css(%(a[href="#{new_session_path}"]))
    assert_equal I18n.t("home.follow_sign_in"), link.text
    expected = I18n.t("home.follow_hint_html", sign_in: I18n.t("home.follow_sign_in"))
    assert_equal expected, hint.text.strip
  end

  test "the search hit count is announced" do
    get root_path(q: "zzz-nothing-matches")

    expected = I18n.t("search.results_for", count: 0, query: "zzz-nothing-matches")
    status = page.css("p").find { _1.text.strip == expected }
    refute_nil status, "no count line"
    assert_equal "status", status["role"], "the count line is not a status"
  end

  test "an empty neighbourhood says so and offers the citywide feed" do
    get root_path(neighborhood_id: @neighborhood.id)

    assert_includes response.body, I18n.t("empty.no_neighborhood_posts")
    assert page.at_css(%(a[href="#{root_path(neighborhood_id: '')}"])), "no way back to the citywide feed"
    assert_select "a", text: I18n.t("home.citywide", city: @city.name)
  end

  test "the chosen neighbourhood is remembered on the next visit until the citywide feed is chosen" do
    elsewhere = Neighborhood.create!(city: @city, name: "Laksevåg #{SecureRandom.hex(2)}",
                                     slug: "laksevag-#{SecureRandom.hex(3)}")
    author = User.strict_loading(false).create!(email_address: "hood_#{SecureRandom.hex(3)}@brgen.no",
                                                password: "password123", username: "hood_#{SecureRandom.hex(3)}",
                                                guest: false)
    Post.create!(user: author, title: "Fra Laksevåg", content: "Nabolagsnytt fra Laksevåg", neighborhood: elsewhere)

    get root_path(neighborhood_id: @neighborhood.id)
    get root_path

    assert_equal @neighborhood.id.to_s, page.at_css("select#home-neighborhood option[selected]")&.[]("value")
    refute_includes response.body, "Nabolagsnytt fra Laksevåg"

    get root_path(neighborhood_id: "")
    get root_path

    assert_nil page.at_css("select#home-neighborhood option[selected]")
    assert_includes response.body, "Nabolagsnytt fra Laksevåg"
  end
end
