# frozen_string_literal: true

class UsersController < ApplicationController
  def show
    @user = User.includes(:creator_profile, :profile, :privacy_setting).find(params[:id])
    visible = WardrobeVisibilityPolicy.new(viewer: Current.user, owner: @user).can_view_wardrobe?
    @items = if visible
      @user.items.with_photos_for_display.recent.limit(12)
    else
      Item.none
    end
    @outfits = visible ? @user.outfits.order(created_at: :desc).limit(6) : Outfit.none
    @posts = @user.posts.recent.limit(10).includes(:outfit, :item, user: :profile)
  end
end
