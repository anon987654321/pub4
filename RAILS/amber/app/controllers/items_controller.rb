# frozen_string_literal: true

class ItemsController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_real_user
  before_action :set_item, only: %i[show edit update destroy spark_joy declutter wear archive restore]
  before_action :authorize!, only: %i[edit update destroy spark_joy declutter wear archive restore]
  skip_before_action :verify_authenticity_token, only: [ :share ]

  def index
    scope = Current.user.items.with_attached_photos.recent
    scope = apply_live_search(scope, columns: %w[title brand category color material], vertical: "wardrobe") if live_search_query.present?
    @pagy, @items = pagy(scope)
    @analytics = WardrobeAnalyticsService.new(Current.user).summary
    finish_live_search(partial: "items/live_search_results")
  end

  def show
    @item.record_activity!("AmberItemViewed", source_vertical: "amber")
  end

  def new
    @item = Current.user.items.build
  end

  def create
    @item = Current.user.items.build(item_params)
    if @item.save
      WardrobeMediaJob.enqueue_for(@item.id) if @item.photos.attached?
      @item.record_activity!("AmberItemCreated", source_vertical: "amber")
      redirect_to(@item, notice: "Item added")
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def edit; end

  def update
    if @item.update(item_params)
      WardrobeMediaJob.enqueue_for(@item.id) if @item.photos.attached?
      @item.record_activity!("AmberItemUpdated", source_vertical: "amber")
      redirect_to(@item, notice: "Updated")
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    @item.record_activity!("AmberItemRemoved", source_vertical: "amber")
    @item.destroy
    redirect_to items_path, notice: "Removed from wardrobe"
  end

  def share
    @item = Current.user.items.build(
      title: share_title,
      category: Item::CATEGORIES.first || "Tops",
      price: nil
    )
    attach_shared_photos(@item)

    if @item.save
      @item.record_activity!("AmberItemShared", source_vertical: "amber")
      redirect_to edit_item_path(@item), notice: "Shared into your wardrobe draft"
    else
      redirect_to new_item_path, alert: "Could not create item draft"
    end
  end

  def spark_joy
    @item.update!(spark_joy: true)
    @item.record_activity!("AmberItemSparkedJoy", source_vertical: "amber")
    redirect_to items_path, notice: "This item sparks joy!"
  end

  def declutter
    @item.update!(spark_joy: false)
    @item.record_activity!("AmberItemDecluttered", source_vertical: "amber")
    redirect_to items_path, notice: "Marked for declutter"
  end

  def archive
    @item.update!(lifecycle_state: "sentimental_archive")
    redirect_to @item, notice: "Archived. You can restore this item at any time."
  end

  def restore
    @item.update!(lifecycle_state: "active")
    redirect_to @item, notice: "Restored to your active wardrobe."
  end

  def wear
    @item.wear!
    @item.record_activity!("AmberItemWorn", source_vertical: "amber")
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

  def set_item = @item = Item.includes(:user).find(params[:id])

  def authorize!
    redirect_to(items_path, alert: "Unauthorized") unless @item.user_id == Current.user&.id
  end

  def item_params
    params.require(:item).permit(
      :title, :category, :color, :size, :material,
      :brand, :price, :times_worn, :purchase_date,
      :mood_effect, :life_phase, :occasion_tags, :season,
      photos: []
    )
  end

  def share_title
    params[:title].presence || params[:text].presence || params[:url].presence || "Shared item"
  end

  def attach_shared_photos(item)
    Array.wrap(params[:files] || params[:file] || params[:photos]).compact.each do |file|
      item.photos.attach(file)
    end
  end
end
