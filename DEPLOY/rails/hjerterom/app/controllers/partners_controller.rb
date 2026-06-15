# frozen_string_literal: true

class PartnersController < ApplicationController
  before_action :require_authentication
  before_action :set_partner, only: %i[show edit update]

  def index
    @partners = Partner.active.order(:name)
    @transfers = Transfer.recent.includes(:partner, :beneficiary, :box).limit(20)
  end

  def show
    @transfers = @partner.transfers.recent.includes(:beneficiary, :box)
  end

  def new
    @partner = Partner.new
  end

  def create
    @partner = Partner.new(partner_params)
    @partner.save ? redirect_to(@partner, notice: "Partner created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @partner.update(partner_params) ? redirect_to(@partner, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  private

  def set_partner
    @partner = Partner.find(params[:id])
  end

  def partner_params
    params.expect(partner: %i[name kind contact_email address notes active])
  end
end