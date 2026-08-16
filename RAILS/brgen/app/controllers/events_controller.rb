# frozen_string_literal: true

class EventsController < ApplicationController
  include Shared::LiveSearchable
  # Event includes Shared::Sluggable, so to_param is the slug — the same trap
  # that made every vote from a feed card 404. See VotesController.
  include Shared::FindableBySlug

  allow_unauthenticated_access only: %i[index show]
  before_action :require_real_user, only: %i[new create edit update destroy cancel]
  before_action :set_event, only: %i[show edit update destroy cancel]
  before_action :authorize_organiser, only: %i[edit update destroy cancel]

  def index
    scope = Event.upcoming.includes(:user, :place, :neighborhood).with_attached_cover
    scope = apply_live_search(scope, columns: %w[title description venue_name], vertical: "events") if live_search_query.present?
    scope = scope.where(neighborhood_id: params[:neighborhood_id]) if params[:neighborhood_id].present?
    @pagy, @events = pagy(scope)
    # Shown as a separate strip rather than mixed in: an archive and a listing
    # answer different questions, and interleaving them is how you end up
    # scrolling past last month to find tonight.
    @past = Event.past.includes(:user).limit(6)
    @my_rsvps = rsvp_status_by_event_id(@events)
    finish_live_search(partial: "events/live_search_results")
  end

  def show
    raise ActiveRecord::RecordNotFound unless @event.readable_by?(Current.user)

    @rsvp = @event.rsvp_for(Current.user)
    @attendees = @event.rsvps.going.includes(:user).limit(24)
    @comments = @event.comments.includes(:user).order(created_at: :desc)
    @comment = Comment.new if Current.user.present?
    @nearby = nearby_events
  end

  def new
    @event = Event.new(starts_at: 1.week.from_now.change(hour: 19, min: 0))
  end

  def create
    @event = Event.new(event_params)
    @event.user = Current.user
    if @event.save
      # The organiser is going to their own event. Saying so avoids an event
      # that reads "0 going" the moment it is posted.
      @event.rsvps.create!(user: Current.user, status: "going")
      redirect_to @event, notice: t("flash.event_created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @event.update(event_params)
      redirect_to @event, notice: t("flash.event_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Cancelling is not deleting: people have it in their calendar, and an event
  # that vanishes tells them nothing. cancel! notifies everyone who said they
  # were coming.
  def cancel
    @event.cancel!
    redirect_to @event, notice: t("flash.event_cancelled")
  end

  def destroy
    @event.destroy
    redirect_to events_path, notice: t("flash.event_removed")
  end

  private

  def set_event
    @event = find_by_slug_or_id(Event.includes(:user, :place, :neighborhood), params[:id])
  end

  def authorize_organiser
    # user_id, not user: @event is loaded by slug with nothing preloaded, and
    # strict_loading_by_default raises on the association read.
    return if Current.user && Current.user.id == @event.user_id

    redirect_to @event, alert: t("shared.flash.not_authorized")
  end

  # One query for the whole page rather than an rsvp_for per card.
  def rsvp_status_by_event_id(events)
    return {} if Current.user.blank? || events.blank?

    EventRsvp.where(user_id: Current.user.id, event_id: events.map(&:id))
             .pluck(:event_id, :status).to_h
  end

  def nearby_events
    return Event.none unless @event.latitude && @event.longitude

    Event.upcoming.where.not(id: @event.id)
         .nearby(@event.latitude, @event.longitude, 5)
         .limit(4)
  end

  def event_params
    params.require(:event).permit(
      :title, :description, :starts_at, :ends_at, :venue_name, :address,
      :place_id, :neighborhood_id, :latitude, :longitude, :capacity,
      :price_cents, :currency, :external_url, :cover
    )
  end
end
