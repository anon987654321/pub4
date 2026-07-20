# frozen_string_literal: true

require "test_helper"

class PostModerationServiceTest < ActiveSupport::TestCase
  test "approves on timeout without raising" do
    post = Post.new(title: "Hello", content: "Neighborhood meetup Saturday")
    service = PostModerationService.new(post)
    service.define_singleton_method(:moderate_sync) { raise Timeout::Error }

    assert service.approve?
  end
end
