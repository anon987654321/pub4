# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_user
        if (session_record = Session.find_by(id: cookies.signed[:session_id]))
          self.current_user = session_record.user
          return true
        end

        # Soft guests (Craigslist-style): session cookie holds guest_user_id
        # even without a signed Session row.
        guest_id = request.session[:guest_user_id]
        return false unless guest_id

        guest = User.find_by(id: guest_id, guest: true)
        return false unless guest

        self.current_user = guest
        true
      end
  end
end
