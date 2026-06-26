# frozen_string_literal: true

require "test_helper"

class BlogsControllerTest < ActionDispatch::IntegrationTest
  def test_root_renders_blog_index
    get root_url
    assert_response :success
  end
end