# frozen_string_literal: true

class TransfersController < ApplicationController
  before_action :require_authentication

  def create
    transfer = Transfer.create!(transfer_params.merge(status: :pending, scheduled_at: Time.current))
    redirect_to partner_path(transfer.partner), notice: "Transfer scheduled"
  end

  def optimize_route
    stops = Partner.active.map { |p| { id: p.id, name: p.name, latitude: p.latitude, longitude: p.longitude } }
    @route = OsrmRouteService.optimize_stops(stops)
    render :optimize_route
  end

  private

  def transfer_params
    params.expect(transfer: %i[partner_id beneficiary_id box_id items_count notes])
  end
end