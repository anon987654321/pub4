# frozen_string_literal: true

class OutfitsController < ApplicationController
  before_action :require_authentication
  before_action :set_outfit, only: %i[show edit update destroy like reorder share]
  before_action :authorize!, only: %i[edit update destroy share]

  def index
    @pagy, @outfits = pagy(Current.user.outfits.order(created_at: :desc))
  end

  def dressing_room
    base = Current.user.items.active_wardrobe.with_attached_photos
    @zones = {
      head:   base.where(category: "Accessories"),
      top:    base.where(category: %w[Tops Outerwear]),
      bottom: base.where(category: %w[Bottoms Dresses]),
      shoes:  base.where(category: "Shoes")
    }
  end

  def show; end

  def new
    @outfit = Current.user.outfits.build
  end

  def create
    @outfit = Current.user.outfits.build(outfit_params)
    @outfit.save ? redirect_to(@outfit, notice: "Outfit created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

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

  def reorder
    positions = params.require(:positions)
    positions.each_with_index do |item_id, index|
      @outfit.outfit_items.where(item_id:).update_all(position: index)
    end
    head :ok
  end

  private

  def set_outfit = @outfit = Outfit.find(params[:id])

  def authorize!
    redirect_to(outfits_path, alert: "Unauthorized") unless @outfit.user == Current.user
  end

  def outfit_params
    params.require(:outfit).permit(:name, :description, :category, :season, :occasion)
  end
end
