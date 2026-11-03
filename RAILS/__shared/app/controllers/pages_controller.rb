# frozen_string_literal: true

# Privacy / terms / cookies for every host app. Public by design — a privacy
# policy behind a login helps no one. Content lives in the views.
class PagesController < ApplicationController
  # The public pages every app serves without an account; config/routes/legal.rb
  # draws a route for each.
  PAGES = %w[privacy terms cookies safety].freeze

  helper Shared::Safety

  allow_unauthenticated_access only: :show if respond_to?(:allow_unauthenticated_access)

  def show
    @page = params[:page].to_s
    raise ActionController::RoutingError, "no such page" unless PAGES.include?(@page)

    render @page
  end
end
