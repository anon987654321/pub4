# frozen_string_literal: true

class VolunteersController < ApplicationController
  before_action :require_real_user
  before_action :set_volunteer, only: %i[show update]

  def index
    @volunteers = Volunteer.available.order(:name)
  end

  def show
    @shifts = @volunteer.shifts.future
    @volunteer.record_activity!("VolunteerViewed", source_vertical: "hjerterom")
  end

  def new
    @volunteer = Volunteer.new
  end

  def create
    @volunteer = Volunteer.new(volunteer_params)
    if @volunteer.save
      @volunteer.record_activity!("VolunteerCreated", source_vertical: "hjerterom")
      respond_to do |format|
        format.html { redirect_to @volunteer }
        format.turbo_stream
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @volunteer.update(volunteer_params)
      @volunteer.record_activity!("VolunteerUpdated", source_vertical: "hjerterom")
      respond_to do |f|
        f.html { redirect_to @volunteer }
        f.turbo_stream
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_volunteer
    @volunteer = Volunteer.find(params[:id])
  end

  def volunteer_params
    params.require(:volunteer).permit(:name, :email, :phone, :active, :notes)
  end
end
