# frozen_string_literal: true

require "test_helper"

# A report files a review case against what it names. The shared controller
# called a globalid method that does not exist, so every report raised.
class ReportTest < ActionDispatch::IntegrationTest
  setup do
    @reader = User.strict_loading(false).create!(email_address: "reader-#{SecureRandom.hex(4)}@amber.test",
                                                 password: "password123")
    author = User.strict_loading(false).create!(email_address: "author-#{SecureRandom.hex(4)}@amber.test",
                                                password: "password123")
    @post = Post.create!(user: author, body: "<p>Et innlegg</p>")
    post session_path, params: { email_address: @reader.email_address, password: "password123" }
  end

  test "reporting a post files a review case and sends the reader back" do
    assert_difference -> { Shared::ReviewCase.count }, 1 do
      post reports_path, params: { target_gid: @post.to_signed_global_id.to_s, reason: "abuse" }
    end

    assert_response :redirect
    review_case = Shared::ReviewCase.last
    assert_equal [ "Post", @post.id ], [ review_case.reviewable_type, review_case.reviewable_id ]
  end

  test "a tampered signature is not found, not a server error" do
    assert_no_difference -> { Shared::ReviewCase.count } do
      post reports_path, params: { target_gid: "not-a-signed-id", reason: "abuse" }
    end

    assert_response :not_found
  end
end
