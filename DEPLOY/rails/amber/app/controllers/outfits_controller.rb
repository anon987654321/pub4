# frozen_string_literal: true

class OutfitsController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_authentication
  before_action :set_outfit, only: %i[show edit update destroy like reorder share wear]
  before_action :authorize!, only: %i[edit update destroy share wear]

  def index
    scope = Current.user.outfits.includes(:items).order(created_at: :desc)
    scope = apply_live_search(scope, columns: %w[name description category season occasion], vertical: "outfits") if live_search_query.present?
    @pagy, @outfits = pagy(scope)
  end

  def dressing_room
    @event = params[:event].presence
    suggestion = WeatherOutfitService.suggest_for(Current.user, event: @event)
    @weather = suggestion[:weather]
    @season = suggestion[:season]
    @zones = suggestion[:zones]
  end

  def show
    respond_to_cached_show(@outfit, only: %i[id name description category season occasion likes_count])
  end

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

  def wear
    @outfit.touch
    redirect_to @outfit, notice: "Marked as worn again!"
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
    params.expect(:outfit => [:name, :description, :category, :season, :occasion])
  end
end
