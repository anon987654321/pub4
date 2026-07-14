# frozen_string_literal: true

class DemoWardrobeController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  before_action :require_demo!

  def index
    @demo_user = Amber::DemoWardrobe.user
    @pagy, @items = pagy(Amber::DemoWardrobe.items.recent)
    @outfits = Amber::DemoWardrobe.outfits.limit(6)
  end

  def show
    @item = Amber::DemoWardrobe.items.find(params[:id])
  end

  private

  def require_demo!
    return if Amber::DemoWardrobe.available?

    redirect_to root_path, alert: "Demo wardrobe is not available yet."
  end
end
