# frozen_string_literal: true

class WardrobeItemsController < ApplicationController
  before_action :set_wardrobe_item, only: %i[show edit update destroy]

  def index
    @wardrobe_items = WardrobeItem.includes(:item).recent.limit(100)
  end

  def show
  end

  def new
    @wardrobe_item = WardrobeItem.new
  end

  def create
    @wardrobe_item = WardrobeItem.new(wardrobe_item_params)
    @wardrobe_item.user = current_user if respond_to?(:current_user, true)

    if @wardrobe_item.save
      redirect_to wardrobe_items_path, notice: t("amber.wardrobe_item_created", default: "Item added")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @wardrobe_item.update(wardrobe_item_params)
      redirect_to wardrobe_items_path, notice: t("amber.wardrobe_item_updated", default: "Item updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @wardrobe_item.destroy
    redirect_to wardrobe_items_path, notice: t("amber.wardrobe_item_deleted", default: "Item removed")
  end

  private

  def set_wardrobe_item
    @wardrobe_item = WardrobeItem.find(params[:id])
  end

  def wardrobe_item_params
    params.expect(:wardrobe_item => [:item_id, :acquisition_date, :condition, :notes])
  end
end
