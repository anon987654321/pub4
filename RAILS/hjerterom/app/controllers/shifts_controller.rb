# frozen_string_literal: true

class ShiftsController < ApplicationController
  before_action :require_real_user
  before_action :set_volunteer, only: %i[create]
  before_action :set_shift, only: %i[update]

  def index
    @shifts = Shift.future
  end

  def create
    @shift = @volunteer.shifts.build(shift_params)
    if @shift.save
      @shift.record_activity!("ShiftCreated", source_vertical: "hjerterom")
      respond_to do |f|
        f.html { redirect_to volunteer_path(@volunteer) }
        f.turbo_stream
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @shift.update(shift_params)
      @shift.record_activity!("ShiftUpdated", source_vertical: "hjerterom")
      respond_to do |f|
        f.html { redirect_to shifts_path }
        f.turbo_stream
      end
    else
      render :index, status: :unprocessable_entity
    end
  end

  private

  def set_volunteer
    @volunteer = Volunteer.find(params[:volunteer_id])
  end

  def set_shift
    @shift = Shift.find(params[:id])
  end

  def shift_params
    params.require(:shift).permit(:starts_at, :ends_at, :kind, :state, :notes)
  end
end
