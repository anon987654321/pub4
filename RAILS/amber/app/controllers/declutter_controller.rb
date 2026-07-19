# frozen_string_literal: true

class DeclutterController < ApplicationController
  before_action :require_real_user
  before_action :set_item, only: %i[review update_review move challenge complete_challenge outcome last_chance create_last_chance_outfit]

  def index
    @summary = DeclutterDashboardService.new(Current.user).summary
    @duplicates = DuplicateDetectorService.new(Current.user).ranked_groups
    @overdue_challenges = DeclutterChallenge.where(user: Current.user).overdue.includes(:item)
    @active_challenges = DeclutterChallenge.where(user: Current.user).active.includes(:item)
    @aging_box = Current.user.items.declutter_box.select { |item| box_age_days(item) >= 30 }
    @box_items = Current.user.items.declutter_box.order(updated_at: :asc).limit(24)
  end

  def review
    @review = @item.declutter_review || @item.build_declutter_review(user: Current.user)
    @score = @item.declutter_score
    @action = DeclutterActionRouter.new(@item).action
    @last_chance = LastChanceOutfitService.new(@item).suggestions
  end

  def update_review
    review = @item.declutter_review || @item.build_declutter_review(user: Current.user)
    review.update!(review_params)
    redirect_to review_declutter_path(@item), notice: "Declutter review saved"
  end

  def move
    action = params[:target].presence || DeclutterActionRouter.new(@item).action[:recommendation]
    state = lifecycle_state_for(action)
    attrs = { lifecycle_state: state }
    if state == "declutter_box"
      meta = @item.metadata.is_a?(Hash) ? @item.metadata.dup : {}
      meta["declutter_box_at"] ||= Date.current.iso8601
      attrs[:metadata] = meta
      attrs[:spark_joy] = false if @item.has_attribute?(:spark_joy)
    end
    @item.update!(attrs)
    redirect_to declutter_index_path, notice: "#{@item.title} moved to #{state.humanize.downcase}"
  end

  def challenge
    challenge = @item.declutter_challenges.create!(
      user: Current.user,
      due_on: params[:due_on].presence || 7.days.from_now.to_date,
      note: params[:note].presence || "Wear once before deciding."
    )
    redirect_to review_declutter_path(@item), notice: "Wear-it-this-week challenge created for #{challenge.due_on}"
  end

  def complete_challenge
    challenge = @item.declutter_challenges.active.order(:due_on).first || @item.declutter_challenges.order(created_at: :desc).first
    challenge&.complete!
    redirect_to @item, notice: "Challenge completed — item marked worn"
  end

  def outcome
    @item.create_declutter_outcome!(outcome_params.merge(user: Current.user))
    redirect_to declutter_index_path, notice: "Declutter outcome recorded"
  end

  def last_chance
    render json: LastChanceOutfitService.new(@item).suggestions
  end

  def create_last_chance_outfit
    suggestions = LastChanceOutfitService.new(@item).suggestions
    suggestion = suggestions[params[:index].to_i] || suggestions.first
    unless suggestion
      return redirect_to(review_declutter_path(@item), alert: "No last-chance combination available")
    end

    outfit = Current.user.outfits.create!(
      name: "Last chance · #{@item.title}",
      description: suggestion[:reason].to_s,
      occasion: @item.occasions.first
    )
    Item.where(id: suggestion[:item_ids], user_id: Current.user.id).each_with_index do |piece, index|
      outfit.outfit_items.create!(item: piece, position: index)
    end
    redirect_to outfit, notice: "Last-chance outfit created — wear it before you decide."
  end

  private

  def set_item
    @item = Current.user.items.find(params[:id])
  end

  def review_params
    params.require(:declutter_review).permit(:reason_kept, :decision, :notes)
  end

  def outcome_params
    params.require(:declutter_outcome).permit(:action, :amount_recovered, :notes)
  end

  def lifecycle_state_for(action)
    case action
    when "keep" then "active"
    when "wear_this_week" then "active"
    when "replace_gradually" then "active"
    when "repair" then "repair"
    when "sell" then "resale"
    when "donate" then "donate"
    when "sentimental_archive" then "sentimental_archive"
    when "release" then "released"
    else "declutter_box"
    end
  end

  def box_age_days(item)
    raw = item.metadata.is_a?(Hash) ? item.metadata["declutter_box_at"] : nil
    boxed = begin
      Date.parse(raw.to_s)
    rescue ArgumentError, TypeError
      item.updated_at.to_date
    end
    (Date.current - boxed).to_i
  end
  helper_method :box_age_days
end
