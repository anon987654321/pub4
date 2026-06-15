# frozen_string_literal: true

class ActivityEventsController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    scope = ActivityEvent.visible.recent
    scope = scope.where(source_vertical: params[:vertical]) if params[:vertical].present?
    scope = scope.where(locality: params[:locality]) if params[:locality].present?
    @pagy, @events = pagy(scope)
  end
end
