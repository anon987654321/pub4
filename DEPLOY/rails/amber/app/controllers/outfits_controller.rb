# frozen_string_literal: true

class OutfitsController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_authentication
  before_action :set_outfit, only: %i[show edit update destroy like reorder share wear]
  before_action :authorize!, only: %i[edit update destroy share wear]

  def index
    scope = Current.user.outfits.order(created_at: :desc)
    if live_search_query.present?
      scope = apply_live_search(scope, columns: %w[name season category occasion], vertical: "outfits")
      item_ids = Current.user.items.where("title LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(live_search_query)}%").pluck(:id)
      scope = scope.joins(:outfit_items).where(outfit_items: { item_id: item_ids }).distinct if item_ids.any?
    end
    @pagy, @outfits = pagy(scope)
  end

  def dressing_room
    base = Current.user.items.active_wardrobe.with_attached_photos
    @zones = {
      head:   base.where(category: "Accessories"),
      top:    base.where(category: %w[Tops Outerwear]),
      bottom: base.where(category: %w[Bottoms Dresses]),
      shoes:  base.where(category: "Shoes"),
    }
  end

  def show; end

  def new
    @outfit = Current.user.outfits.build
    @outfit.outfit_items.build if @outfit.outfit_items.empty?
  end

  def create
    @outfit = Current.user.outfits.build(outfit_params)
    @outfit.save ? redirect_to(@outfit, notice: "Outfit created") : render(:new, status: :unprocessable_entity)
  end

  def edit
    @outfit.outfit_items.build if @outfit.outfit_items.empty?
  end

  def update
    @outfit.update(outfit_params) ? redirect_to(@outfit, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @outfit.destroy
    redirect_to outfits_path, notice: "Outfit deleted"
  end

  def like
    @outfit.like!
    redirect_to @outfit
  end

  def share
    body = "Outfit: #{@outfit.name}\n\nItems:\n#{@outfit.items.map { |i| "- #{i.title}" }.join("\n")}"
    post = Current.user.posts.build(body: body, outfit_id: @outfit.id)
    if post.save
      redirect_to post, notice: "Outfit shared to brgen!"
    else
      redirect_to @outfit, alert: "Could not share: #{post.errors.full_messages.to_sentence}"
    end
  end

  def wear
    @outfit.touch
    redirect_to @outfit, notice: "Marked as worn again!"
  end

  def reorder
    positions = params.require(:positions)
    positions.each_with_index do |item_id, index|
      @outfit.outfit_items.where(item_id: item_id).update_all(position: index)
    end
    head :ok
  end

  private

  def set_outfit
    @outfit = Outfit.find(params[:id])
  end

  def authorize!
    redirect_to(outfits_path, alert: "Unauthorized") unless @outfit.user == Current.user
  end

  def outfit_params
    params.require(:outfit).permit(:name, :description, :category, :season, :occasion, outfit_items_attributes: %i[id item_id position _destroy])
  end
end
