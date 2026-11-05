# frozen_string_literal: true

require "application_system_test_case"

# The city stream carries every new post in the city into #feed-pending, and the
# chip counted all of them. A feed filtered to one neighbourhood, or the media
# wall, offered "1 nytt innlegg" for a post it would never show.
class FeedUpdatesFilterTest < ApplicationSystemTestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @here = Neighborhood.create!(city: @city, name: "Her #{SecureRandom.hex(2)}", slug: "her-#{SecureRandom.hex(3)}")
  end

  # What a broadcast does: a staged card lands in the pending list.
  def stage(id, neighborhood:, media:)
    card = %(<turbo-frame id="post_#{id}" data-neighborhood-id="#{neighborhood}" data-media="#{media}"></turbo-frame>)
    page.execute_script("document.getElementById('feed-pending').insertAdjacentHTML('afterbegin', arguments[0])", card)
  end

  def chip = find("#feed-panel [data-feed-updates-target=chip]", visible: :all)

  test "a feed filtered to a neighbourhood counts only that neighbourhood's new posts" do
    visit root_path(neighborhood_id: @here.id)

    stage(990_001, neighborhood: @here.id + 1, media: false)
    stage(990_002, neighborhood: "", media: false)
    assert chip[:hidden], "a post from elsewhere in the city was counted"

    stage(990_003, neighborhood: @here.id, media: false)
    assert_selector "#feed-panel [data-feed-updates-target=count]", text: I18n.t("home.new_posts.one")
  end

  test "the media wall counts only new posts with media" do
    # neighborhood_id: blank, because the home page remembers the last filter in
    # the session, and the test before this one chose a neighbourhood whose id
    # the rolled-back database hands out again.
    visit root_path(view: "media", neighborhood_id: "")

    stage(990_004, neighborhood: "", media: false)
    assert chip[:hidden], "a text post was counted on the media wall"

    stage(990_005, neighborhood: "", media: true)
    assert_selector "#feed-panel [data-feed-updates-target=count]", text: I18n.t("home.new_posts.one")
  end
end
