# frozen_string_literal: true

class CreatorWardrobeItemsController < ApplicationController
  before_action :require_real_user
  before_action :set_profile

  def create
    item = Current.user.items.find(params[:item_id])
    showcase = @profile.creator_wardrobe_items.find_or_initialize_by(item: item)
    showcase.caption = params[:caption].to_s.strip.presence
    showcase.position = @profile.creator_wardrobe_items.count
    if showcase.save
      redirect_to edit_my_creator_profile_path, notice: "Item added to showcase"
    else
      redirect_to edit_my_creator_profile_path, alert: "Could not add item"
    end
  end

  def destroy
    showcase = @profile.creator_wardrobe_items.find(params[:id])
    showcase.destroy!
    redirect_to edit_my_creator_profile_path, notice: "Item removed from showcase"
  end

  private

  def set_profile
    @profile = CreatorProfile.find_by(user: Current.user) || redirect_to(new_my_creator_profile_path)
  end
end