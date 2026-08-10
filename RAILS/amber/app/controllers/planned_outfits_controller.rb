# frozen_string_literal: true

class PlannedOutfitsController < ApplicationController
  before_action :require_real_user

  def index
    @pagy, @planned = pagy(Current.user.planned_outfits.upcoming.includes(:outfit))
    @outfits = Current.user.outfits.order(:name)
  end

  def create
    @plan = Current.user.planned_outfits.build(plan_params)
    if @plan.save
      @plan.record_activity!("AmberPlannedOutfitCreated", source_vertical: "amber")
      redirect_to(planned_outfits_path, notice: "Planned")
    else
      redirect_to(planned_outfits_path, alert: @plan.errors.full_messages.first)
    end
  end

  def destroy
    plan = Current.user.planned_outfits.find(params[:id])
    plan.record_activity!("AmberPlannedOutfitRemoved", source_vertical: "amber")
    plan.destroy!
    redirect_to planned_outfits_path
  end

  private

  def plan_params = params.require(:planned_outfit).permit(:outfit_id, :planned_date, :notes)
end
