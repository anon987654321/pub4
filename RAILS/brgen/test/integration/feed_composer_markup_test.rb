# frozen_string_literal: true

require "test_helper"

# The quick composer on the front page: its draft survives a close, it counts
# what is written beside the Live cap, and it asks before discarding work.
class FeedComposerMarkupTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    host! "brgen.no"
    get root_path
    assert_response :success
    @launcher = Nokogiri::HTML(response.body).at_css(".compose-launcher")
  end

  test "the draft is kept by the shared draft store" do
    form = @launcher.at_css("dialog form.composer-form")

    assert_includes form["data-controller"].split, "draft-store"
    assert_equal "brgen-feed-compose", form["data-draft-store-key-value"]
  end

  test "the composer counts what is written beside the Live cap" do
    body = @launcher.at_css(".composer-body")

    assert_includes body["data-controller"].split, "character-counter"
    assert_equal "input", body.at_css("textarea")["data-character-counter-target"]
    refute_nil body.at_css("[data-character-counter-target=counter]")
    assert_includes body.text, I18n.t("feed.compose_live_limit", count: Post::LIVE_CONTENT_MAX)
  end

  test "closing asks first, by button, backdrop or Esc" do
    assert_equal I18n.t("feed.compose_discard"), @launcher["data-feed-compose-discard-value"]
    assert_includes @launcher.at_css("dialog")["data-action"], "cancel->feed-compose#cancel"
  end
end
