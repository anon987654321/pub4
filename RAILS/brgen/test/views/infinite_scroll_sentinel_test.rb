# frozen_string_literal: true

require "test_helper"

# shared/_infinite_scroll_sentinel pages every feed. It paged only for a reader
# who scrolled to the bottom edge, announced "Laster mer…" on every page load
# (its loading text sat inside an aria-live region from the start), and when
# the list ran out it ended without a word.
class InfiniteScrollSentinelTest < ActionView::TestCase
  Page = Struct.new(:next, :page)

  def sentinel(pagy)
    render partial: "shared/infinite_scroll_sentinel",
           locals: { pagy:, reflex: "HomeInfiniteScrollReflex#load_more" }
    Nokogiri::HTML5.fragment(rendered)
  end

  test "a keyboard or switch user can page with a button" do
    html = sentinel(Page.new(2, 1))

    button = html.at_css(".infinite-scroll-sentinel button[type=button][data-action='infinite-scroll#appear']")
    refute_nil button, "the sentinel offers no Load more button"
    assert_equal I18n.t("status.load_more"), button.text.strip
  end

  test "the loading text is not on the page until a page is loading" do
    html = sentinel(Page.new(2, 1))

    status = html.at_css(".infinite-scroll-sentinel [role=status][data-infinite-scroll-target=status]")
    refute_nil status, "the sentinel has no status target for the loading text"
    assert_equal "", status.text.strip, "the status announces on page load"
    assert_nil html.at_css(".infinite-scroll-sentinel[aria-live]"),
               "the whole sentinel is a live region again, button and all"
    assert_equal I18n.t("status.loading_more"),
                 html.at_css(".infinite-scroll-sentinel")["data-infinite-scroll-loading-value"]
  end

  test "the last page of a paged list says it is the end" do
    html = sentinel(Page.new(nil, 3))

    assert_nil html.at_css(".infinite-scroll-sentinel")
    assert_equal I18n.t("status.end_of_list"), html.at_css("p.infinite-scroll-end")&.text&.strip
  end

  test "a list that fits on one page carries no end line" do
    assert_nil sentinel(Page.new(nil, 1)).at_css(".infinite-scroll-end")
  end

  test "the reflex replaces the sentinel with the end line on the last page" do
    source = File.read(Rails.root.join("../__shared/app/reflexes/shared/infinite_scroll_reflex.rb"))

    assert_match(/cable_ready\.outer_html\(selector:, html: end_of_list_html\)/, source)
    refute_match(/cable_ready\.remove\(selector:\)/, source)
  end
end
