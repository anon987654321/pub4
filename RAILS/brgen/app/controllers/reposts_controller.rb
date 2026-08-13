# frozen_string_literal: true

# Toggle on POST, matching VotesController and the `action` Stimulus controller,
# which only ever sends POST. A second press removes the repost.
class RepostsController < ApplicationController
  # Post includes Shared::Sluggable, whose to_param returns the slug — so
  # post_repost_path(post) carries "sol-pa-floyen", not an id, and a plain
  # find(params[:post_id]) raises RecordNotFound on every press.
  include Shared::FindableBySlug

  rate_limit to: 60, within: 1.minute, only: :create,
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  before_action :require_user_session

  def create
    post = find_by_slug_or_id(Post.kept, params[:post_id])
    repost = Current.user.reposts.find_by(post_id: post.id)

    if repost
      repost.destroy
    else
      Current.user.reposts.create!(post: post)
    end

    # The memo was populated before this request changed the answer.
    Current.reposted_post_ids = nil
    @post = post.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path }
    end
  end
end
