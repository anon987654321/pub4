# frozen_string_literal: true

class ReadingPlansController < ApplicationController
  before_action :require_authentication
  before_action :set_plan, only: %i[show complete_day]

  def index
    @plans = Current.user.reading_plans.includes(:reading_plan_days).order(created_at: :desc)
  end

  def show
    @today = @plan.reading_plan_days.ordered.find { |d| d.scheduled_on == Date.current && !d.completed? } ||
      @plan.reading_plan_days.ordered.find { |d| !d.completed? }
  end

  def new
    @plan = ReadingPlan.new(duration_days: 30)
  end

  def create
    @plan = Current.user.reading_plans.build(plan_params)
    if @plan.save
      ReadingPlanGenerationJob.perform_later(@plan.id)
      redirect_to @plan, notice: "Reading plan created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def complete_day
    day = @plan.reading_plan_days.find(params[:day_id])
    day.update!(completed_at: Time.current)
    redirect_to @plan, notice: "Day completed"
  end

  private

  def set_plan
    @plan = Current.user.reading_plans.find(params[:id])
  end

  def plan_params
    params.expect(reading_plan: %i[name duration_days])
  end
end