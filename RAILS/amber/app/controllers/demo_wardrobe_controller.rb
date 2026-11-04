# frozen_string_literal: true

class DemoWardrobeController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  before_action :require_demo!

  def index
    @demo_user = Amber::DemoWardrobe.user
    @pagy, @items = pagy(Amber::DemoWardrobe.items.with_photos_for_display.recent)
    @outfits = Amber::DemoWardrobe.outfits.with_images_for_display.limit(6)
    # Mix & Match, read-only: a guest can rotate the demo's garments with no
    # account to save a look into.
    @zones = Amber::DressingRoom.zones_for(@demo_user.items.in_rotation, ranker: TasteRanker.new(@demo_user))
  end

  def show
    @item = Amber::DemoWardrobe.items.with_photos_for_display.find(params[:id])
  end

  private

  def require_demo!
    return if Amber::DemoWardrobe.available?

    redirect_to root_path, alert: t("flash.demo_wardrobe_unavailable")
  end
end
