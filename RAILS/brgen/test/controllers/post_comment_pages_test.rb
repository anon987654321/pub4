# frozen_string_literal: true

require "test_helper"

# A post's thread pages its root comments: every root loaded at once made a
# popular post's page grow without bound.
class PostCommentPagesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @author = User.strict_loading(false).create!(email_address: "pcp_#{SecureRandom.hex(3)}@brgen.no",
                                                 password: "password123", guest: false, city: @city)
    @post = Post.create!(user: @author, title: "Mange svar", content: "Si din mening", city: @city)
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the thread shows thirty root comments and pages to the rest" do
    now = Time.current
    rows = (1..35).map do |n|
      { user_id: @author.id, commentable_type: "Post", commentable_id: @post.id, content: "Svar-#{n}-slutt",
        created_at: now - n.minutes, updated_at: now - n.minutes }
    end
    Comment.insert_all!(rows)

    get post_path(@post, sort: "new")

    assert_select "#comments > turbo-frame > article.comment", 30
    assert_select "nav.pager a[rel=next][href*=?]", "comments_page=2"

    get post_path(@post, sort: "new", comments_page: 2)
    assert_select "#comments > turbo-frame > article.comment", 5
  end
end
