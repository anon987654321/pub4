# frozen_string_literal: true

module ApplicationCable
  class Channel < ActionCable::Channel::Base
    # A connection with nobody behind it (Connection#allow_anonymous_connection?)
    # may read public Turbo streams and nothing here: every channel built on
    # this one, StimulusReflex's included, acts for a user.
    before_subscribe :reject, unless: :current_user
  end
end
