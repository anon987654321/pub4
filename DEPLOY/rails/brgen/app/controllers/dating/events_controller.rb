# frozen_string_literal: true

module Dating
  class EventsController < BaseController
    before_action :require_user_session, only: %i[new create rsvp]
    before_action :set_event, only: %i[show rsvp]

    def index
      city = session[:city_override_city] || Current.city
      @events = Dating::Event.upcoming.in_city(city).limit(50)
      if Current.user&.dating_profile
        prof = Current.user.dating_profile
        @events = @events.nearby(prof.latitude, prof.longitude)
      end
    end

    def show
      @rsvp = @event.rsvps.find_by(user: Current.user) if authenticated?
    end

    def new
      @event = Dating::Event.new(city: Current.city, starts_at: 1.week.from_now)
    end

    def create
      @event = Dating::Event.new(event_params)
      @event.user = Current.user
      if @event.save
        redirect_to dating_event_path(@event), notice: "Event created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def rsvp
      require_user_session
      rsvp = @event.rsvps.find_or_initialize_by(user: Current.user)
      rsvp.status = params[:status].presence_in(Dating::EventRsvp::STATUSES) || "going"
      rsvp.save!
      redirect_to dating_event_path(@event), notice: "RSVP saved"
    end

    private

    def set_event
      @event = Dating::Event.find(params[:id])
    end

    def event_params
      params.expect(dating_event: %i[title description venue city starts_at ends_at latitude longitude])
    end
  end
end