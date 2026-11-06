# frozen_string_literal: true

# What a person's posts and comments have earned in votes.
#
# This was `users.karma`, an integer column recomputed on every vote and
# rendered by nothing — `karma` appeared in no view, helper or partial in any
# app or engine. It also paid for that invisibility: `update_karma!` ran two
# joined SUMs and then wrote `updated_at` alongside the value, busting every
# `cache [user, …]` fragment for the author, justified by a comment claiming
# "karma renders on the profile and on every post byline". It did not.
#
# So brgen carried two reputation stores. This is the same number in the one
# that is wired: `reputation_scores`, unique per (user, scope), which TrustScore
# already writes as scope "global". Trust is what we know about a person;
# content is what their writing earned. Different questions, one table, and a
# third store was the alternative.
class ContentScore
  SCOPE = "content"

  def initialize(user:, scope: SCOPE)
    @scope = scope
    @user = user
  end

  def call
    row = user.reputation_scores.find_or_initialize_by(scope: scope)
    row.update!(calculated_at: Time.current, score: votes_on_authored_content)
    row
  end

  private

  attr_reader :scope, :user

  # Two joins rather than a polymorphic one: votes.votable_type is the
  # discriminator and SQLite will not index across it, so each half is a plain
  # join that can use votes(votable_type, votable_id).
  def votes_on_authored_content
    posts = Vote.joins("JOIN posts ON posts.id = votes.votable_id AND votes.votable_type = 'Post'")
                .where(posts: { user_id: user.id }).sum(:value)
    comments = Vote.joins("JOIN comments ON comments.id = votes.votable_id AND votes.votable_type = 'Comment'")
                   .where(comments: { user_id: user.id }).sum(:value)
    posts + comments
  end
end
