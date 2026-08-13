# frozen_string_literal: true

class StoriesController < ApplicationController
  allow_unauthenticated_access only: %i[index show]
  before_action :require_user_session, only: %i[new create destroy]

  def index
    @rings = Story.rings_for(Current.user)
  end

  def show
    # `alive` rather than a plain find: an expired story is gone as far as every
    # surface is concerned, whether or not the sweep has run yet. Otherwise the
    # link keeps working for as long as the job is behind.
    @story = Story.alive.includes(:user).find(params[:id])
    @story.view_by!(Current.user)
    @ring = Story.alive.where(user_id: @story.user_id).newest_first.to_a
    @viewers = @story.story_views.includes(:user).limit(50) if own_story?
  end

  def new
    @story = Story.new
  end

  def create
    @story = Story.new(story_params)
    @story.user = Current.user
    if @story.save
      redirect_to story_path(@story), notice: t("flash.story_posted")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    story = Current.user.stories.find(params[:id])
    story.destroy
    redirect_to stories_path, notice: t("flash.story_removed")
  end

  private

  def own_story? = Current.user.present? && Current.user.id == @story.user_id

  def story_params
    # No latitude/longitude from the client: the position is the one
    # locations#update already stored, coarsened there.
    params.require(:story).permit(:caption, :media, :attach_area)
  end
end
