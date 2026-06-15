# frozen_string_literal: true

class ImpactController < ApplicationController
  allow_unauthenticated_access

  def show
    @stats = {
      meals_provided: FoodItem.where.not(box_id: nil).sum(:quantity),
      beneficiaries_served: Beneficiary.active.count,
      donations_received: Donation.count,
      food_rescued_kg: FoodListing.available.sum(:quantity),
      partners_active: Partner.active.count,
      transfers_completed: Transfer.delivered.count
    }
    @recent_transfers = Transfer.recent.includes(:partner, :beneficiary).limit(10)
  end
end