class HomeController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    @crisis_lines  = Crisis.where(available_24h: true).limit(5)
    @food_listings = FoodListing.available.order(created_at: :desc).limit(6)
    @recent_posts  = Post.recent.includes(:user, :category).limit(5)
    @resources     = Resource.verified.limit(8)
  end
end
