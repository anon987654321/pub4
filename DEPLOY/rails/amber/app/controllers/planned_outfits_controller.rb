# frozen_string_literal: true

class PlannedOutfitsController < ApplicationController
  before_action :require_authentication

  def index
    @planned = Current.user.planned_outfits.upcoming.includes(:outfit)
    @outfits = Current.user.outfits.order(:name)
  end

  def create
    @plan = Current.user.planned_outfits.build(plan_params)
    @plan.save ? redirect_to(planned_outfits_path, notice: "Planned") : redirect_to(planned_outfits_path, alert: @plan.errors.full_messages.first)
  end

  def destroy
    Current.user.planned_outfits.find(params[:id]).destroy!
    redirect_to planned_outfits_path
  end

  private

  def plan_params = params.expect(:planned_outfit => [:outfit_id, :planned_date, :notes])
end
