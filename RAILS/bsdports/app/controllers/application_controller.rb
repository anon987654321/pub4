# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Shared::ApplicationSetup

  # The layout carries the signed-in nav, and a 304 keeps the page, forms and
  # CSRF token the browser first stored. Every conditional GET is keyed on the
  # viewer so signing in or out never revalidates the other state's copy.
  etag { Current.user&.id if authenticated? }
end
