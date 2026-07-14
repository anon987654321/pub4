# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @plans = catalog.plans
    @legat_count = catalog.legats.size
    @applicant = catalog.applicant
  end
end