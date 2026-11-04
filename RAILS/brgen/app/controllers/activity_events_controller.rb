# frozen_string_literal: true

class ActivityEventsController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    present_actors = { guest: false, deleted_at: nil, deletion_scheduled_at: nil }
    @events = ActivityEvent.visible.public_only.readable_by(Current.user)
                           .joins(:actor).where(users: present_actors).recent.limit(100)
    @events = @events.where(source_vertical: params[:vertical]) if params[:vertical].present?
    @events = @events.where(locality: params[:locality]) if params[:locality].present?
  end
end
