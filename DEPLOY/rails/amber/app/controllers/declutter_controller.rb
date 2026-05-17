class DeclutterController < ApplicationController
  before_action :require_authentication
  before_action :set_item, only: %i[review update_review move challenge complete_challenge outcome last_chance]

  def index
    @summary = DeclutterDashboardService.new(Current.user).summary
    @duplicates = DuplicateDetectorService.new(Current.user).ranked_groups
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
    @item.update!(lifecycle_state: state)
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
end
