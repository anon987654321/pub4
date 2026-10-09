# frozen_string_literal: true

require "test_helper"

# The search palette sits over every brgen page, ahead of <main>, and a Turbo
# Stream lands on the first element carrying its target id. While the palette
# shared #live_search_results and #search_suggestions with the index pages, a
# search on posts, communities, events, maps, tv, playlist or conversations
# streamed its results into the closed palette instead of the page.
class SearchPaletteTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "an index page owns the only results and suggestions slots its stream targets" do
    get communities_path
    assert_response :success

    assert_select "#live_search_results", 1
    assert_select "#search_suggestions", 1
    assert_select "main #live_search_results", 1
    assert_select ".search_palette ##{SearchController::PALETTE_RESULTS}", 1
    assert_select ".search_palette ##{SearchController::PALETTE_SUGGESTIONS}", 1
  end

  test "the palette's search box and the page's own never share an id, and neither autocompletes" do
    get communities_path
    assert_response :success

    assert_select "input#q", 1
    assert_select ".search_palette input#search_palette_q[autocomplete=off]", 1
    assert_select "main input#q[autocomplete=off]", 1
  end

  test "the palette's search streams into the palette's own slots" do
    get global_search_path(q: "bergen", surface: SearchController::PALETTE), headers: STREAM

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, %(<turbo-stream action="update" target="#{SearchController::PALETTE_RESULTS}">)
    assert_includes response.body, %(<turbo-stream action="update" target="#{SearchController::PALETTE_SUGGESTIONS}">)
  end

  test "people search excludes accounts leaving the service" do
    leaving = User.create!(
      email_address: "search-leaving-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123",
      username: "search_leaving_#{SecureRandom.hex(3)}"
    )
    leaving.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    get global_search_path(q: "search_leaving_")

    assert_response :success
    refute_includes response.body, leaving.username
  end

  test "the palette exposes the whole city network" do
    get communities_path

    assert_select ".search_palette_cities .city-network-item", Brgen::DomainRegistry::CITY_NETWORK_DOMAINS.size
    assert_select ".search_palette_cities a[href='https://lsangeles.com/']", 1
  end

  test "the mobile More sheet exposes the same city network" do
    get communities_path

    assert_select ".mobile-sheet-cities .city-network-item", Brgen::DomainRegistry::CITY_NETWORK_DOMAINS.size
    assert_select "#mobile-sheet-cities-title", 1
  end

  test "the palette form says where it is searching from" do
    get communities_path

    assert_select ".search_palette form input[type=hidden][name=surface][value=?]", SearchController::PALETTE
  end

  test "a no-match hint is Norwegian" do
    get global_search_path
    html = @controller.view_context.render(partial: "shared/search_suggestions", locals: { suggestions: [ "bergen" ] })

    assert_includes html, I18n.t("search.no_exact_matches", locale: :nb)
    assert_not_includes html, "No exact matches"
  end
end
