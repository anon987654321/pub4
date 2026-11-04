# frozen_string_literal: true

class UsersController < ApplicationController
  def show
    @user = User.publicly_visible.includes(:creator_profile, :profile, :privacy_setting).find(params[:id])
    visible = WardrobeVisibilityPolicy.new(viewer: Current.user, owner: @user).can_view_wardrobe?
    @items = visible ? recent_items : Item.none
    @outfits = visible ? recent_outfits : Outfit.none
    @posts = @user.posts.recent.limit(10).includes(:outfit, :item, user: :profile)
  end

  private

  def recent_items
    items = @user.items.with_photos_for_display
    items.recent.limit(12)
  end

  # The outfit card reads each outfit's image and its items' photos.
  def recent_outfits
    outfits = @user.outfits.with_images_for_display
    outfits.order(created_at: :desc).limit(6)
  end
end
