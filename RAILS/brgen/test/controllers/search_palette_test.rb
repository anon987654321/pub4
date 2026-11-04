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

  test "the palette exposes only TLS-ready city network entries" do
    get communities_path

    assert_select ".search_palette_cities .city-network-item", Brgen::DomainRegistry.live_network_entries.size
    assert_select ".search_palette_cities a[href='https://oshlo.no/']", 1
    assert_select ".search_palette_cities a[href='https://lndon.uk/']", 0
    assert_select ".search_palette_cities a[href='https://lsangeles.com/']", 0
  end

  test "the mobile More sheet exposes the same TLS-ready city network" do
    get communities_path

    assert_select ".mobile-sheet-cities .city-network-item", Brgen::DomainRegistry.live_network_entries.size
    assert_select ".mobile-sheet-cities a[href='https://lndon.uk/']", 0
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

  # A block holds in search too: neither the person blocked nor the person who
  # blocked the reader is offered as a result.
  test "people search leaves out both sides of a block" do
    tag = "srchblk_#{SecureRandom.hex(3)}"
    people = %w[me blocked blocker open].to_h do |role|
      user = User.create!(email_address: "#{tag}-#{role}@brgen.no", password: "password123", username: "#{tag}_#{role}")
      [ role, user ]
    end
    people["me"].block!(people["blocked"])
    people["blocker"].block!(people["me"])
    post session_path, params: { email_address: people["me"].email_address, password: "password123" }

    get global_search_path(q: tag)

    assert_response :success
    assert_includes response.body, people["open"].username
    refute_includes response.body, people["blocked"].username
    refute_includes response.body, people["blocker"].username
  end

  # Every committed search was stored for the palette and nothing let the
  # reader take them back.
  test "a reader can clear their recent searches from the palette" do
    reader = User.create!(email_address: "srch-clear-#{SecureRandom.hex(3)}@brgen.no", password: "password123",
                          username: "srch_clear_#{SecureRandom.hex(3)}")
    SearchRecent.record!(reader, "sykkel")
    post session_path, params: { email_address: reader.email_address, password: "password123" }

    get communities_path
    assert_select ".search_palette_recents form[action=?]", clear_recent_searches_path

    delete clear_recent_searches_path
    assert_response :redirect
    assert_empty SearchRecent.recent_for(reader)
  end
end
