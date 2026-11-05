# frozen_string_literal: true

require "test_helper"

# Past the depth cap every further reply was drawn flat at depth 4, so a long
# back-and-forth read as one undifferentiated column. Replies under a comment at
# the cap fold behind "Continue thread" instead.
class CommentContinueThreadTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"

    @author = User.strict_loading(false).create!(email_address: "deep-#{SecureRandom.hex(4)}@brgen.no",
                                                 username: "deep_#{SecureRandom.hex(3)}", password: "password123",
                                                 city: @city)
    @post = Post.create!(user: @author, city: @city, title: "Dyp tråd", content: "…")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  # A comment and n replies, each answering the one before.
  def build_chain(length)
    chain = []
    length.times do |n|
      chain << Comment.create!(user: @author, commentable: @post, content: "nivå #{n}", parent_id: chain.last&.id)
    end
    chain
  end

  test "replies deeper than the cap sit behind Continue thread" do
    chain = build_chain(7)

    get post_path(@post)

    assert_response :success
    # Depths 0..4 draw open; the reply to the depth-4 comment is folded.
    (0..3).each { |n| assert_select "#replies_comment_#{chain[n].id}", 1 }
    assert_select "details.comment-continue #replies_comment_#{chain[4].id} #comment_#{chain[5].id}"
    assert_select "#comment_#{chain[4].id} details.comment-continue > summary", text: "Fortsett tråden (1 svar)"
    assert_select "#comment_#{chain[3].id} > article > details.comment-continue", 0
  end

  test "a comment at the cap with no replies keeps an open, empty reply target" do
    chain = build_chain(5)

    get post_path(@post)

    assert_select "#replies_comment_#{chain[4].id}", 1
    assert_select "details.comment-continue", 0
  end
end
