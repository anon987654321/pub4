# frozen_string_literal: true

class AnalyticsController < ApplicationController
  before_action :require_authentication

  def show
    @dashboard = WardrobeAnalyticsService.dashboard_for(Current.user)
  end
end