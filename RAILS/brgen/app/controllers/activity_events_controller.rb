# frozen_string_literal: true

class ActivityEventsController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    @events = ActivityEvent.visible.public_only.joins(:actor).where(users: { guest: false, deleted_at: nil, deletion_scheduled_at: nil }).recent.limit(100)
    @events = @events.where(source_vertical: params[:vertical]) if params[:vertical].present?
    @events = @events.where(locality: params[:locality]) if params[:locality].present?
  end
end
