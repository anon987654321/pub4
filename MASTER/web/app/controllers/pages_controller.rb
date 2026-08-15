# frozen_string_literal: true

class PagesController < ApplicationController
  def radio_bergen
    # There is no radio_bergen.html in this tree. The face still publishes
    # client_action radio_open → /radio_bergen, and the live radio is the
    # playlist vertical. Sending people to a 404 was the whole feature.
    redirect_to "https://playlist.brgen.no/", allow_other_host: true, status: :see_other
  end
end
