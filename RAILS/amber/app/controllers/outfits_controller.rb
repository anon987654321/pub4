# frozen_string_literal: true

class OutfitsController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_real_user
  before_action :set_outfit, only: %i[show edit update destroy like reorder share wear]
  before_action :authorize!, only: %i[edit update destroy share wear]

  def index
    scope = Current.user.outfits.with_attached_image.includes(items: { photos_attachments: :blob }).order(created_at: :desc)
    if live_search_query.present?
      scope = apply_live_search(scope, columns: %w[name season category occasion], vertical: "outfits")
      item_ids = Current.user.items.where("title LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(live_search_query)}%").pluck(:id)
      scope = scope.joins(:outfit_items).where(outfit_items: { item_id: item_ids }).distinct if item_ids.any?
    end
    @pagy, @outfits = pagy(scope)
    @weather = WeatherService.today
    @default_weather = weather_prompt(@weather)
    finish_live_search(partial: "outfits/live_search_results")
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

  def generate
    weather = params[:weather].presence || weather_prompt(WeatherService.today)
    outfit = OutfitGenerationService.new(Current.user).generate!(
      weather: weather,
      season: params[:season].presence || season_from_month,
      occasion: params[:occasion]
    )
    outfit ? redirect_to(outfit, notice: "Outfit generated") : redirect_to(outfits_path, alert: "Add wardrobe items before generating outfits")
  end

  def show
    @outfit.record_activity!("AmberOutfitViewed", source_vertical: "amber")
  end

  def new
    @outfit = Current.user.outfits.build
    @outfit.outfit_items.build if @outfit.outfit_items.empty?
  end

  def create
    @outfit = Current.user.outfits.build(outfit_params)
    if @outfit.save
      Shared::DomainEvent.record!(actor: Current.user, action: "outfit.created", subject: @outfit, source_vertical: "amber") if defined?(Shared::DomainEvent)
      redirect_to(@outfit, notice: "Outfit created")
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def edit
    @outfit.outfit_items.build if @outfit.outfit_items.empty?
  end

  def update
    if @outfit.update(outfit_params)
      Shared::DomainEvent.record!(actor: Current.user, action: "outfit.updated", subject: @outfit, source_vertical: "amber") if defined?(Shared::DomainEvent)
      redirect_to(@outfit, notice: "Updated")
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    @outfit.record_activity!("AmberOutfitRemoved", source_vertical: "amber")
    @outfit.destroy
    redirect_to outfits_path, notice: "Outfit deleted"
  end

  def like
    @outfit.like!
    @outfit.record_activity!("AmberOutfitLiked", source_vertical: "amber")
    redirect_to @outfit
  end

  def share
    body = "Outfit: #{@outfit.name}\n\nItems:\n#{@outfit.items.map { |i| "- #{i.title}" }.join("\n")}"
    post = Current.user.posts.build(body: body, outfit_id: @outfit.id)
    if post.save
      @outfit.record_activity!("AmberOutfitShared", source_vertical: "amber")
      redirect_to post, notice: "Outfit shared to brgen!"
    else
      redirect_to @outfit, alert: "Could not share: #{post.errors.full_messages.to_sentence}"
    end
  end

  def wear
    @outfit.touch
    @outfit.record_activity!("AmberOutfitWorn", source_vertical: "amber")
    redirect_to @outfit, notice: "Marked as worn again!"
  end

  def reorder
    positions = params.require(:positions)
    positions.each_with_index do |item_id, index|
      @outfit.outfit_items.where(item_id: item_id).update_all(position: index)
    end
    @outfit.record_activity!("AmberOutfitReordered", source_vertical: "amber")
    head :ok
  end

  private

  def set_outfit
    @outfit = Outfit.includes(:user).find(params[:id])
  end

  def authorize!
    redirect_to(outfits_path, alert: "Unauthorized") unless @outfit.user_id == Current.user&.id
  end

  def outfit_params
    params.require(:outfit).permit(:name, :description, :category, :season, :occasion, outfit_items_attributes: %i[id item_id position _destroy])
  end

  def weather_prompt(weather)
    return nil unless weather.is_a?(Hash)

    parts = [ weather[:description], weather[:temp] ? "#{weather[:temp].round}°C" : nil ].compact
    parts.join(", ").presence
  end

  def season_from_month
    m = Time.current.month
    case m
    when 3..5 then "Spring"
    when 6..8 then "Summer"
    when 9..11 then "Autumn"
    else "Winter"
    end
  end
end
