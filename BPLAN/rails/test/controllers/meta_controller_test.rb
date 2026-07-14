# frozen_string_literal: true

require "test_helper"

class MetaControllerTest < ActionDispatch::IntegrationTest
  test "sitemap xml" do
    get sitemap_url(format: :xml)
    assert_response :success
    assert_includes response.body, "<urlset"
    assert_includes response.body, "/plans/master"
  end

  test "robots txt" do
    get robots_url(format: :txt)
    assert_response :success
    assert_includes response.body, "Sitemap:"
  end
end