# frozen_string_literal: true

require "test_helper"

# The global search page past its first sections: events and communities are
# searched too, every section is named in the reader's language and leads to
# that vertical's own search, and a post shows where the word was found.
class SearchVerticalsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
    @word = "fjellrev#{SecureRandom.hex(3)}"
    @author = User.create!(email_address: "sokv-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
                           username: "sokv_#{SecureRandom.hex(3)}")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def section_heading(vertical, count)
    I18n.t("search.section_heading", vertical: I18n.t("search.sections.#{vertical}"), count:)
  end

  test "an upcoming event and a public community are found, a private one is not" do
    Event.create!(user: @author, city: @city, title: "Konsert #{@word}", starts_at: 2.days.from_now)
    Event.create!(user: @author, city: @city, title: "Ferdig #{@word}", starts_at: 3.days.ago, ends_at: 2.days.ago)
    Community.create!(user: @author, city: @city, name: "Klubb #{@word}", slug: "klubb-#{SecureRandom.hex(4)}")
    Community.create!(user: @author, city: @city, name: "Hemmelig #{@word}", slug: "hemmelig-#{SecureRandom.hex(4)}",
                      privacy: "private")

    get global_search_path(q: @word)

    assert_response :success
    assert_select "h2", text: section_heading(:events, 1)
    assert_select "h2", text: section_heading(:communities, 1)
    assert_select "li a", text: "Konsert #{@word}"
    assert_select "li a", text: "Ferdig #{@word}", count: 0
    assert_select "li a", text: "Hemmelig #{@word}", count: 0
  end

  test "each section leads to its vertical's own search with the query" do
    Post.create!(user: @author, city: @city, title: "Tur #{@word}", content: "hei")
    Community.create!(user: @author, city: @city, name: "Klubb #{@word}", slug: "klubb-#{SecureRandom.hex(4)}")

    get global_search_path(q: @word)

    assert_select "h2", text: section_heading(:posts, 1)
    assert_select "a[href=?]", posts_path(q: @word),
                  text: I18n.t("search.see_all", vertical: I18n.t("search.sections.posts"))
    assert_select "a[href=?]", communities_path(q: @word),
                  text: I18n.t("search.see_all", vertical: I18n.t("search.sections.communities"))
  end

  test "a vertical on its own subdomain is searched there" do
    get global_search_path(q: @word)

    assert_equal "http://tv.brgen.no/channels?q=#{@word}",
                 @controller.view_context.search_section_href(:videos, @word).sub(/:\d+/, "")
    assert_nil @controller.view_context.search_section_href(:people, @word)
  end

  test "a post result shows the text around the match with the match marked" do
    Post.create!(user: @author, city: @city, title: "Helg",
                 content: "Vi gikk langs fjorden og fikk se en #{@word} ved hytta i går kveld.")

    get global_search_path(q: @word)

    assert_select "li p.search-result-snippet", text: /fikk se en #{@word} ved hytta/
    assert_select "li p.search-result-snippet mark", text: @word
  end
end
