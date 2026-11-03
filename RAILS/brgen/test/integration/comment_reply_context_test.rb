# frozen_string_literal: true

require "test_helper"

# A reply says who it answers, and a comment's age reads as Norwegian does:
# "for 2 timer siden", not a bare "rundt 2 timer".
class CommentReplyContextTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city

    @asker = User.strict_loading(false).create!(email_address: "reply-asker@brgen.no", password: "password123",
                                                username: "spoer", guest: false, city: @city)
    @answerer = User.strict_loading(false).create!(email_address: "reply-answerer@brgen.no", password: "password123",
                                                   username: "svarer", guest: false, city: @city)

    @post = Post.create!(user: @asker, city: @city, title: "Spørsmål", content: "Hvem vet?")
    @question = Comment.create!(user: @asker, commentable: @post, content: "<p>Noen?</p>", created_at: 3.hours.ago)
    @answer = Comment.create!(user: @answerer, commentable: @post, content: "<p>Jeg</p>", parent_id: @question.id)

    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "a reply names the comment it answers and a top-level comment names nobody" do
    get post_path(@post)

    assert_response :success
    assert_select "#comment_#{@answer.id} header", text: /Svarer @spoer/
    assert_select "#comment_#{@question.id} > article > header .comment-replying-to", 0
  end

  test "the age reads with siden and carries the full date" do
    get post_path(@post)

    time = css_select("#comment_#{@question.id} > article > header time").first
    assert_match(/\Afor .+ siden\z/, time.text.strip)
    assert_equal @question.created_at.iso8601, time["datetime"]
    assert time["title"].present?
  end

  test "a reply rendered alone looks its parent up" do
    # As a create response or a broadcast holds it: thread loaded, parent not.
    reply = Comment.preload(:user, :commentable).find(@answer.id)
    html = ApplicationController.render(partial: "comments/comment", locals: { comment: reply })

    assert_includes html, "Svarer @spoer"
  end
end
