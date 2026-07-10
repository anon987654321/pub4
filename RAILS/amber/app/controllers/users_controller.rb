# frozen_string_literal: true

class UsersController < ApplicationController
  def show
    @user    = User.includes(:creator_profile).find(params[:id])
    @items   = @user.items.recent.limit(12)
    @outfits = @user.outfits.order(created_at: :desc).limit(6)
    @posts   = @user.posts.recent.limit(10)
  end
end
