# frozen_string_literal: true

class BoxesController < ApplicationController
  before_action :require_real_user
  before_action :set_box, only: %i[show update]

  def index
    @boxes = Box.open.order(week_start: :desc)
  end

  def show; end

  def new
    @box = Box.new(week_start: Date.current.beginning_of_week)
  end

  def create
    @box = Box.new(box_params)
    if @box.save
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
    params.expect(:box => [:week_start, :beneficiary_id, :notes, :status])
  end
end
