# frozen_string_literal: true

require "test_helper"

# The ports index linked its RSS feed only in the page nav, so feed readers
# and browsers that look for <link rel=alternate> in the head found none.
class PortsFeedDiscoveryTest < ActionDispatch::IntegrationTest
  test "the ports index advertises its feed in the head" do
    get root_url
    assert_response :success
    assert_select "head link[rel=alternate][type='application/rss+xml'][href=?]", ports_url(format: :rss), 1
  end
end
