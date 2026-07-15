# frozen_string_literal: true

module Brgen
  # Brgen alias for shared demo seed media helpers.
  module DemoMedia
    module_function

    def attach_remote!(...)
      Shared::DemoMedia.attach_remote!(...)
    end

    def attach_remote_postpro!(...)
      Shared::DemoMedia.attach_remote_postpro!(...)
    end

    def skip_attach?
      Shared::DemoMedia.skip_attach?
    end
  end
end