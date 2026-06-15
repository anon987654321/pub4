# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include Shared::PunditAuthorization
  include Pagy::Backend
  allow_browser versions: :modern
  turbo_refreshes_with :morph, scroll: :preserve
end
