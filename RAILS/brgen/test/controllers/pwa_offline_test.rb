# frozen_string_literal: true

require "test_helper"

# /offline is what the service worker serves when the visitor has no
# connection. It answered 500 in brgen, amber and bsdports alike, because
# `render partial: "shared/offline_page", layout: "application"` asks Rails for
# a *partial* layout — layouts/_application — which none of these apps have.
# A 500 is the least useful response possible on the one page whose whole job is
# to work when nothing else does.
class PwaOfflineTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    host! "brgen.no"
  end

  test "the offline page renders inside the application layout" do
    get "/offline"

    assert_response :success
    assert_includes response.body, "offline-page"
    # The layout is the point: the previous attempt at this rendered the partial
    # bare, which is what "PWA offline page with zero CSS" in 5beba4b07 was
    # about. Without the layout there is no stylesheet link and the page is
    # unstyled text.
    assert_match(/<link[^>]+stylesheet/, response.body,
                 "offline page rendered without the layout, so it has no CSS")
  end
end
