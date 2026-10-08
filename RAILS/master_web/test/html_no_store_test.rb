# frozen_string_literal: true

require "test_helper"

class HtmlNoStoreTest < ActionDispatch::IntegrationTest
  def test_homepage_has_no_store_cache_control
    get "/"
    assert_response :success
    cache = response.headers["Cache-Control"].to_s.downcase
    assert_includes cache, "no-store"
    assert_nil response.headers["ETag"]
  end
end
