# frozen_string_literal: true

class UsersController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    @user = User.find(params[:id])
    @posts = @user.posts.includes(:category).order(created_at: :desc).limit(20)
    @food_listings = @user.food_listings.order(created_at: :desc).limit(10)
    @volunteer = Volunteer.find_by(user_id: @user.id)
  end
end