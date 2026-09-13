# frozen_string_literal: true

require "test_helper"
class PagesSmokeTest < ActionDispatch::IntegrationTest
  setup { Brgen::CitySeed.sync! if City.table_exists?; host! "brgen.no" }
  test "legal pages render 200" do
    %w[/privacy /terms /cookies].each do |path|
      get path
      assert_response :success, "#{path} failed"
      assert_select "article.legal-prose h1"
    end
  end
  test "homepage renders the legal footer with links" do
    get "/"
    assert_response :success
    assert_select "footer.site-legal a[href=?]", "/privacy"
  end
  # /offline is what the service worker serves with no connection. It answered
  # 500 in all three apps, because `render partial: "shared/offline_page",
  # layout: "application"` asks for a partial layout none of them has. The
  # layout is the point: rendered bare there is no stylesheet link.
  test "the offline page renders inside the application layout" do
    get "/offline"
    assert_response :success
    assert_includes response.body, "offline-page"
    assert_match(/<link[^>]+stylesheet/, response.body, "offline page rendered without the layout, so it has no CSS")
  end

  test "the new post and sign-up forms render their labels from the locale" do
    get "/posts/new"
    assert_response :success
    assert_includes response.body, I18n.t("posts.anywhere_in", city: "Bergen")
    assert_includes response.body, I18n.t("posts.body_label")
    refute_includes response.body, "Anywhere in Bergen"

    get "/users/new"
    assert_response :success
    assert_includes response.body, I18n.t("auth.honeypot_label")
  end
end
