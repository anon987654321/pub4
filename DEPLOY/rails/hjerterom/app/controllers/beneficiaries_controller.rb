# frozen_string_literal: true

class Hjerterom::BeneficiariesController < ApplicationController
  before_action :set_beneficiary, only: [:match, :claim]

  def match
    # AN1103: beneficiary matching
    @matches = FoodItem.available
      .where("dietary_tags && ARRAY[?]::varchar[]", @beneficiary.dietary_restrictions || [])
      .limit(5)
    # TODO: weight by location, expiry
  end

  def claim
    @item = FoodItem.find(params[:item_id])
    if @item.update(beneficiary: @beneficiary, status: "claimed")
      redirect_to beneficiary_path(@beneficiary), notice: "Claimed!"
    end
  end

  private

  def set_beneficiary = (@beneficiary = Beneficiary.find(params[:id]))
end
