# frozen_string_literal: true

class BoxesController < ApplicationController
  before_action :require_real_user
  before_action :set_box, only: %i[show update]

  def index
    @boxes = Box.open.order(week_start: :desc)
  end

  def show
    @box.record_activity!("BoxViewed", source_vertical: "hjerterom")
  end

  def new
    @box = Box.new(week_start: Date.current.beginning_of_week)
  end

  def create
    @box = Box.new(box_params)
    if @box.save
      @box.record_activity!("BoxCreated", source_vertical: "hjerterom")
      respond_to do |f|
        f.html { redirect_to @box }
        f.turbo_stream
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @box.update(box_params)
      @box.record_activity!("BoxUpdated", source_vertical: "hjerterom")
      respond_to do |f|
        f.html { redirect_to @box }
        f.turbo_stream
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_box
    @box = Box.find(params[:id])
  end

  def box_params
    params.require(:box).permit(:week_start, :beneficiary_id, :notes, :status)
  end
end
