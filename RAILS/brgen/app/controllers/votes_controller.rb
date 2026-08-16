# frozen_string_literal: true

# Brgen-specific VotesController.
# See shared for Reactable/Votable concern. Local controller kept for
# karma side-effects and city-specific behavior.
# See RAILS/shared/WIRING_NOTES.md "Deferred DRY".
class VotesController < ApplicationController
  # Post includes Shared::Sluggable, so to_param is the slug and
  # post_vote_path(post) carries "sol-pa-floyen". find_votable called
  # Post.find on that, which raises RecordNotFound -> 404, and the action
  # Stimulus controller rolls the optimistic count back on a non-ok response.
  # Every vote cast from a feed card was silently discarded.
  include Shared::FindableBySlug

  rate_limit to: 60, within: 1.minute, only: :create,
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  before_action :require_user_session

  def create
    @votable = find_votable
    vote     = @votable.votes.find_or_initialize_by(user: Current.user)
    value    = params.dig(:vote, :value).to_i

    if vote.persisted? && vote.value == value
      vote.destroy
    else
      vote.update!(value:)
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path }
    end
  end

  private

  def find_votable
    # Comments have no slug column at all, so find_by_slug_or_id would raise on
    # the missing column rather than falling through — id lookup stays.
    if params[:post_id]
      post = find_by_slug_or_id(Post.includes(:community), params[:post_id])
      raise ActiveRecord::RecordNotFound unless post.readable_by?(Current.user)
      return post
    end
    if params[:comment_id]
      comment = Comment.includes(:commentable).find(params[:comment_id])
      record = comment.commentable
      raise ActiveRecord::RecordNotFound if record.respond_to?(:readable_by?) && !record.readable_by?(Current.user)
      return comment
    end
    raise ActiveRecord::RecordNotFound, "no votable in params"
  end
end
