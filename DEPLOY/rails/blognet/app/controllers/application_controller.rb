# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method
  include Shared::CacheableShow

  turbo_refreshes_with :morph
  allow_browser versions: :modern
end
