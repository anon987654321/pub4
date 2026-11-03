# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Shared::CableIdentity

    private

    # Signed-out visitors read the front page and post pages live too. They
    # connect as nobody, and PublicStreams lets them subscribe to those pages'
    # streams and to nothing else.
    def allow_anonymous_connection? = true

    # Soft guests (Craigslist-style): the session cookie carries guest_user_id
    # without a signed Session row, so a guest can hold a live cable connection.
    def set_current_user
      return true if super

      guest_id = request.session[:guest_user_id]
      return false unless guest_id

      guest = User.find_by(id: guest_id, guest: true)
      return false unless guest

      self.current_user = guest
      true
    end
  end
end
