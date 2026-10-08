# frozen_string_literal: true

class HashtagsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    normalized = params[:name].to_s.downcase.gsub(/[^a-z0-9_]/, "")
    @hashtag = Hashtag.find_by(name: normalized)
    raise ActiveRecord::RecordNotFound unless @hashtag

    scope = Post.kept.visible_to(Current.user)
                .where(id: Tagging.where(hashtag_id: @hashtag.id, taggable_type: "Post").select(:taggable_id))
                .hot
                .with_attached_image
                .includes(:user, :community, :votes)
    @pagy, @posts = pagy(scope)
    @city_communities = Community.popular_cached(limit: 6)
  end
end
