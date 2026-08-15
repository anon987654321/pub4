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
      respond_to do |format|
        format.turbo_stream { load_planner }
        format.html { redirect_to(planned_outfits_path, notice: t("flash.outfit_planned")) }
      end
    else
      redirect_to(planned_outfits_path, alert: @plan.errors.full_messages.first)
    end
  end

  def destroy
    @plan = Current.user.planned_outfits.find(params[:id])
    @plan.record_activity!("AmberPlannedOutfitRemoved", source_vertical: "amber")
    @plan.destroy!
    respond_to do |format|
      format.turbo_stream { load_planner }
      format.html { redirect_to planned_outfits_path }
    end
  end

  private

  def plan_params
    permitted = params.require(:planned_outfit).permit(:outfit_id, :planned_date, :notes)
    unless Current.user.outfits.exists?(id: permitted[:outfit_id])
      permitted[:outfit_id] = nil
    end
    permitted
  end

  def load_planner
    @pagy, @planned = pagy(Current.user.planned_outfits.upcoming.includes(:outfit))
    @outfits = Current.user.outfits.order(:name)
  end
end
