# frozen_string_literal: true

class WardrobeItemsController < ApplicationController
  before_action :require_real_user
  before_action :set_wardrobe_item, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[show edit update destroy]

  def index
    @wardrobe_items = WardrobeItem.includes(:item).recent.limit(100)
  end

  def analytics
    @analytics = WardrobeAnalytics.new(Current.user).summary
    @recommendations = Current.user.recommendations.active.recent.limit(12)
  end

  def timeline
    @timeline = StyleEvolution.new(Current.user).timeline
  end

  def show
    @wardrobe_item.record_activity!("AmberWardrobeItemViewed", source_vertical: "amber")
  end

  def new
    @wardrobe_item = WardrobeItem.new
  end

  def create
    @wardrobe_item = Current.user.wardrobe_items.build(wardrobe_item_params)

    if @wardrobe_item.save
      @wardrobe_item.record_activity!("AmberWardrobeItemCreated", source_vertical: "amber")
      redirect_to wardrobe_items_path, notice: t("amber.wardrobe_item_created", default: "Item added")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @wardrobe_item.update(wardrobe_item_params)
      @wardrobe_item.record_activity!("AmberWardrobeItemUpdated", source_vertical: "amber")
      redirect_to wardrobe_items_path, notice: t("amber.wardrobe_item_updated", default: "Item updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @wardrobe_item.record_activity!("AmberWardrobeItemRemoved", source_vertical: "amber")
    @wardrobe_item.destroy
    redirect_to wardrobe_items_path, notice: t("amber.wardrobe_item_deleted", default: "Item removed")
  end

  private

  def set_wardrobe_item
    @wardrobe_item = WardrobeItem.find(params[:id])
  end

  def authorize!
    redirect_to(wardrobe_items_path, alert: "Unauthorized") unless @wardrobe_item.user == Current.user
  end

  def wardrobe_item_params
    params.require(:wardrobe_item).permit(:item_id, :acquisition_date, :condition, :notes)
  end
end
