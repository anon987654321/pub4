# frozen_string_literal: true

# What a live page missed while its cable was down: a phone asleep in a
# pocket, a tab in the background, a train through a tunnel. Broadcasts sent
# meanwhile are gone for good, so on reconnect the page asks for everything
# newer than the newest it holds and adds it the way the stream would have.
#
# Rendered for this reader, with their own vote and repost state: unlike a
# broadcast, a response has exactly one viewer.
class PostCatchUpsController < ApplicationController
  include Shared::FindableBySlug

  # A page that slept longer than this is better served by its own reload,
  # which the chip and the thread both still allow.
  FEED_LIMIT = 25
  COMMENT_LIMIT = 100

  # New posts for the front page's pending chip: the same set the city stream
  # carries (kept, never a private community's), oldest first so each prepend
  # leaves the newest on top.
  def feed
    # From zero when the city had no post at all when the page was rendered.
    @posts = missed_posts
    render formats: :turbo_stream
  end

  # New comments for a post page, in the order they were written so a reply
  # never arrives before its parent. The thread is rendered whole, so the
  # newest comment on the page is the newest there was.
  def comments
    @post = find_by_slug_or_id(Post.includes(:community), params[:post_id])
    raise ActiveRecord::RecordNotFound unless @post.readable_by?(Current.user)

    # From zero when the page held no comment: the whole thread is what it missed.
    @comments = missed_comments
    render formats: :turbo_stream
  end

  private

  def after_id = params[:after].to_i

  def missed_posts
    public_posts = without_blocked(Post.kept.visible_to(nil))
    fresh = public_posts.where(posts: { id: (after_id + 1).. }).order(:id).limit(FEED_LIMIT)
    with_media = fresh.with_attached_image.with_attached_images
    with_media.includes(:user, :community, :votes)
  end

  # The reader's blocks, as HomeFeed applies them to the feed. A post with no
  # user is kept: NOT IN alone would drop it with the blocked ones.
  def without_blocked(posts)
    hidden = Array(Current.user&.blocked_user_ids)
    hidden.any? ? posts.where(user_id: nil).or(posts.where.not(user_id: hidden)) : posts
  end

  def missed_comments
    thread = @post.comments.kept
    fresh = thread.where(comments: { id: (after_id + 1).. }).order(:id)
    fresh.includes(:user).limit(COMMENT_LIMIT)
  end
end
