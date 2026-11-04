# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Shared::ApplicationSetup
  include Shared::LocalizedRequest

  # The layout carries the signed-in nav, and a 304 keeps the page, forms and
  # CSRF token the browser first stored. Every conditional GET is keyed on the
  # viewer so signing in or out never revalidates the other state's copy, and
  # on the language, so switching it never revalidates the other one's.
  etag { Current.user&.id if authenticated? }
  etag { I18n.locale }
end
