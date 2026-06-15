# frozen_string_literal: true

class DonationsController < ApplicationController
  before_action :require_real_user
  before_action :set_donation, only: %i[show update destroy]

  def index
    @donations = Donation.active.order(created_at: :desc)
  end

  def show
    respond_to_cached_show(@donation, only: %i[id source_name pickup_window notes status created_at])
  end

  def new
    @donation = Donation.new
  end

  def create
    @donation = Donation.new(donation_params)
    if @donation.save
      respond_to do |f|
        f.html { redirect_to @donation, flash: { toast: "Donasjon registrert — takk!" } }
        f.turbo_stream
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @donation.update(donation_params)
      respond_to do |f|
        f.html { redirect_to @donation }
        f.turbo_stream
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    @donation.destroy!
    redirect_to donations_path
  end

  private

  def set_donation
    @donation = Donation.find(params[:id])
  end

  def donation_params
    params.expect(:donation => [:source_name, :pickup_window, :notes, :status])
  end
end
