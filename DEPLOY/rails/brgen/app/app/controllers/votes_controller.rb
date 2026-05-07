class VotesController < ApplicationController
  before_action :require_authentication

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
    return Post.find(params[:post_id])       if params[:post_id]
    return Comment.find(params[:comment_id]) if params[:comment_id]
    raise ActiveRecord::RecordNotFound, "no votable in params"
  end
end
