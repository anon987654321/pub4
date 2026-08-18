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
end
