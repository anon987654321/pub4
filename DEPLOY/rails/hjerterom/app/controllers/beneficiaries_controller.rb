# frozen_string_literal: true

class BeneficiariesController < ApplicationController
  before_action :require_authentication
  before_action :set_beneficiary, only: %i[show match claim]

  def index
    @pagy, @beneficiaries = pagy(Beneficiary.active.priority_first)
  end

  def show; end

  def match
    restrictions = @beneficiary.dietary_restriction_list
    scope = FoodItem.available.includes(:donation)
    if restrictions.any?
      scope = scope.where(
        restrictions.map { "dietary_tags LIKE ?" }.join(" OR "),
        *restrictions.map { |tag| "%#{tag}%" }
      )
    end
    @matches = scope.order(:best_before).limit(10)
  end

  def claim
    @item = FoodItem.available.find(params[:item_id])
    if @item.update(beneficiary: @beneficiary, status: "claimed")
      redirect_to beneficiary_path(@beneficiary), notice: "Claimed!"
    else
      redirect_to match_beneficiary_path(@beneficiary), alert: "Could not claim item"
    end
  end

  private

  def set_beneficiary = (@beneficiary = Beneficiary.find(params[:id]))
end