# frozen_string_literal: true

class TagsController < ApplicationController
  def show
    @hashtag = Hashtag.find_by!(name: params[:name].to_s.downcase)
    @posts = Post.joins(:hashtags)
                 .where(hashtags: { id: @hashtag.id })
                 .includes(:user, :community, :votes)
                 .order(created_at: :desc)
    @trending_tags = Hashtag.trending.limit(10)
  end
end
