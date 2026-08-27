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
    # Charts are built here rather than folded into the summary: items#index
    # reads the same summary for one chip, and would otherwise pay for four
    # figures it never draws.
    @charts = WardrobeCharts.new(Current.user).figures
    @recommendations = Current.user.recommendations.active.recent.limit(12)
  end

  def organize
    @organization = ClosetOrganization.new(Current.user)
    @grouped = @organization.grouped
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
    return render :edit, status: :unprocessable_entity unless @wardrobe_item.update(wardrobe_item_params)

    @wardrobe_item.record_activity!("AmberWardrobeItemUpdated", source_vertical: "amber")
    redirect_to wardrobe_items_path, notice: t("amber.wardrobe_item_updated", default: "Item updated")
  end

  def destroy
    @wardrobe_item.record_activity!("AmberWardrobeItemRemoved", source_vertical: "amber")
    @wardrobe_item.destroy
    redirect_to wardrobe_items_path, notice: t("amber.wardrobe_item_deleted", default: "Item removed")
  end

  private

  def set_wardrobe_item
    # includes(:item) because the show template opens with
    # `@wardrobe_item.item&.title`, and strict_loading_by_default raises on a
    # lazy association read in every environment. Without it this action was
    # a 500 for everyone, owner included — found the same day as the ownership
    # guard below, which failed the same way one line further down.
    #
    # Preloaded here rather than avoided, unlike the guard: the page genuinely
    # needs the item, so the fix is to fetch it, not to sidestep it.
    @wardrobe_item = WardrobeItem.includes(:item).find(params[:id])
  end

  def authorize!
    # user_id, not user: @wardrobe_item comes from WardrobeItem.find(params[:id])
    # with nothing preloaded, and strict_loading_by_default raises on the
    # association read before the comparison happens — so this guard never ran,
    # and every path behind it failed, the owner's included.
    return if Current.user && Current.user.id == @wardrobe_item.user_id

    redirect_to(wardrobe_items_path, alert: t("shared.flash.not_authorized"))
  end

  def wardrobe_item_params
    params.require(:wardrobe_item).permit(:item_id, :acquisition_date, :condition, :notes)
  end
end
