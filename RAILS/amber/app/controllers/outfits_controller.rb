# frozen_string_literal: true

class OutfitsController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_real_user
  before_action :set_outfit, only: %i[show edit update destroy like reorder share wear]
  # reorder mutates outfit_items via update_all and was set_ but never
  # authorized — any signed-in user could reorder another user's outfit.
  before_action :authorize!, only: %i[edit update destroy share wear reorder]
  # show and like were likewise unauthorized. Gate them on viewability rather
  # than ownership: liking someone else's outfit is legitimate, reading a
  # private wardrobe is not.
  before_action :authorize_view!, only: %i[show like]

  def index
    scope = Current.user.outfits.with_images_for_display.order(created_at: :desc)
    if live_search_query.present?
      scope = apply_live_search(scope, columns: %w[name season category occasion], vertical: "outfits")
      item_ids = Current.user.items.where("title LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(live_search_query)}%").pluck(:id)
      scope = scope.joins(:outfit_items).where(outfit_items: { item_id: item_ids }).distinct if item_ids.any?
    end
    @pagy, @outfits = pagy(scope)
    @weather = Weather.today
    @default_weather = weather_prompt(@weather)
    finish_live_search(partial: "outfits/live_search_results")
  end

  # Mix & Match Magic. Each zone is ordered by TasteRanker rather than by
  # insertion, so the first garment a carousel shows is the one this wardrobe's
  # behaviour says the owner reaches for — that is the "ever-evolving knowledge
  # of your taste" the feature is named for.
  def dressing_room
    # in_rotation: the carousels offer garments to wear, and active_wardrobe
    # keeps declutter-box items, so a garment you had already decided to release
    # kept riding round the Tops zone.
    base = Current.user.items.in_rotation.with_photos_for_display
    ranker = TasteRanker.new(Current.user)
    @zones = Amber::DressingRoom.zones_for(base, ranker: ranker)
    @taste_reasons = @zones.values.flatten.to_h { |item| [ item.id, ranker.explain(item) ] }
  end

  # Save the four garments the carousels are currently showing. Before this the
  # button was a bare link to the blank outfit form, so every combination the
  # user rotated to was thrown away at the moment they tried to keep it.
  def save_look
    ids = Array(params[:item_ids]).map(&:to_i).uniq.reject(&:zero?)
    items = Current.user.items.where(id: ids).to_a
    return redirect_to(dressing_room_outfits_path, alert: t("flash.pick_a_garment_first")) if items.empty?

    outfit = Current.user.outfits.build(
      name: params[:name].presence || default_look_name(items),
      season: season_from_month,
      occasion: params[:occasion].presence
    )
    # Position head-to-toe so the saved outfit reads in the same order the
    # dressing room stacked it on the mannequin.
    zone_order = Amber::DressingRoom::ZONES.keys.each_with_index.to_h
    items.sort_by { |item| [ zone_order.fetch(zone_for(item), zone_order.size), item.id ] }
         .each_with_index { |item, index| outfit.outfit_items.build(item: item, position: index) }

    if outfit.save
      Shared::DomainEvent.record!(actor: Current.user, action: "outfit.created", subject: outfit, source_vertical: "amber") if defined?(Shared::DomainEvent)
      redirect_to outfit, notice: t("flash.look_saved")
    else
      redirect_to dressing_room_outfits_path, alert: outfit.errors.full_messages.to_sentence
    end
  end

  def generate
    weather = params[:weather].presence || weather_prompt(Weather.today)
    outfit = OutfitGeneration.new(Current.user).generate!(
      weather: weather,
      season: params[:season].presence || season_from_month,
      occasion: params[:occasion]
    )
    outfit ? redirect_to(outfit, notice: t("flash.outfit_generated")) : redirect_to(outfits_path, alert: t("flash.add_items_before_generating"))
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
      redirect_to(@outfit, notice: t("flash.outfit_created"))
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def edit
    @outfit.outfit_items.build if @outfit.outfit_items.empty?
  end

  def update
    return render(:edit, status: :unprocessable_entity) unless @outfit.update(outfit_params)

    Shared::DomainEvent.record!(actor: Current.user, action: "outfit.updated", subject: @outfit, source_vertical: "amber") if defined?(Shared::DomainEvent)
    redirect_to(@outfit, notice: t("flash.updated"))
  end

  def destroy
    @outfit.record_activity!("AmberOutfitRemoved", source_vertical: "amber")
    @outfit.destroy
    redirect_to outfits_path, notice: t("flash.outfit_deleted")
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
      redirect_to post, notice: t("flash.outfit_shared_to_brgen")
    else
      redirect_to @outfit, alert: t("flash.outfit_share_failed", errors: post.errors.full_messages.to_sentence)
    end
  end

  def wear
    @outfit.touch
    @outfit.record_activity!("AmberOutfitWorn", source_vertical: "amber")
    redirect_to @outfit, notice: t("flash.marked_as_worn_again")
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
    # privacy_setting is preloaded because authorize_view! consults it via
    # WardrobeVisibilityPolicy; User is strict_loading, so a lazy load raises.
    # items is preloaded for Outfit#total_wears, which sums in Ruby.
    @outfit = Outfit.includes(:items, user: :privacy_setting).find(params[:id])
  end

  def authorize!
    redirect_to(outfits_path, alert: t("shared.flash.not_authorized")) unless @outfit.user_id == Current.user&.id
  end

  def authorize_view!
    return if WardrobeVisibilityPolicy.new(viewer: Current.user, owner: @outfit.user).can_view_wardrobe?

    redirect_to(outfits_path, alert: t("shared.flash.not_authorized"))
  end

  def outfit_params
    params.require(:outfit).permit(:name, :description, :category, :season, :occasion, outfit_items_attributes: %i[id item_id position _destroy])
  end

  def zone_for(item)
    Amber::DressingRoom::ZONES.find { |_zone, categories| categories.include?(item.category) }&.first
  end

  def default_look_name(items)
    lead = items.find { |item| item.category.in?(%w[Tops Dresses Outerwear]) } || items.first
    [ lead.color.presence&.then { |c| c.start_with?("#") ? nil : c }, lead.title, "look" ].compact.join(" ")
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
