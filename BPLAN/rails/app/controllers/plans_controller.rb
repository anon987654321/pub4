# frozen_string_literal: true

class PlansController < ApplicationController
  def index
    @plans = catalog.plans
  end

  def show
    @plan = catalog.plan(params[:slug])
    not_found unless @plan

    @body = catalog.plan_html(@plan[:slug])
    not_found if @body.blank?
  end
end