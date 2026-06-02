# frozen_string_literal: true

class ItemsController < ApplicationController
  before_action :require_authentication
  before_action :set_item, only: %i[show edit update destroy spark_joy declutter wear]
  before_action :authorize!, only: %i[edit update destroy spark_joy declutter wear]

  def index
    @pagy, @items = pagy(Current.user.items.recent)
  end

  def show; end

  def new
    @item = Current.user.items.build
  end

  def create
    @item = Current.user.items.build(item_params)
    if @item.save
      WardrobeMediaJob.perform_later(@item.id) if @item.photos.attached?
      redirect_to(@item, notice: "Item added")
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def edit; end

  def update
    if @item.update(item_params)
      WardrobeMediaJob.perform_later(@item.id) if @item.photos.attached?
      redirect_to(@item, notice: "Updated")
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    @item.destroy
    redirect_to items_path, notice: "Removed from wardrobe"
  end

  def spark_joy
    @item.update!(spark_joy: true)
    redirect_to items_path, notice: "This item sparks joy!"
  end

  def declutter
    @item.update!(spark_joy: false)
    redirect_to items_path, notice: "Marked for declutter"
  end

  def wear
    @item.wear!
    redirect_to @item, notice: "Worn today — +1"
  end

  def archive_seasonal
    Current.user.items.active_wardrobe.find_each(&:archive_out_of_season!)
    redirect_to items_path, notice: "Out-of-season items moved to archive"
  end

  def resurface_seasonal
    Current.user.items.seasonal_archived.find_each(&:resurface_seasonal!)
    redirect_to items_path, notice: "Seasonal items resurfaced if in season"
  end

  def shopping_list
    service = WardrobeGapService.new(Current.user)
    service.create_recommendations!
    @gaps = service.gaps
    @recommendations = Current.user.recommendations.where(kind: "purchase_gap").recent
  end

  private

  def set_item = @item = Item.find(params[:id])

  def authorize!
    redirect_to(items_path, alert: "Unauthorized") unless @item.user == Current.user
  end

  def item_params
    params.require(:item).permit(
      :title, :category, :color, :size, :material,
      :brand, :price, :times_worn, :purchase_date,
      :mood_effect, :life_phase, :occasion_tags, :season,
      photos: []
    )
  end
end
