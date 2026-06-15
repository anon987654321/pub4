# frozen_string_literal: true

class MatchingController < ApplicationController
  before_action :require_authentication

  def show
    @matches = BeneficiaryMatchingService.match_inventory
  end

  def apply
    match = params.require(:match)
    item = FoodItem.find(match[:item_id])
    box = Box.find(match[:box_id])
    item.update!(box:)
    redirect_to matching_path, notice: "Matched #{item.name} to box"
  end
end