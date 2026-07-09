# frozen_string_literal: true

module Shared
  module MasterGuestHome
    extend ActiveSupport::Concern

    private

    def master_guest_home? = action_name == "index" && !authenticated?

    def render_master_guest_home!(title:)
      @master_embed_title = title
      render("shared/master_guest", layout: "master_embed")
    end
  end
end