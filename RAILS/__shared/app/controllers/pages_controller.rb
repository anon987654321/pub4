# frozen_string_literal: true

# Privacy / terms / cookies for every host app. Public by design — a privacy
# policy behind a login helps no one. Content lives in the views.
class PagesController < ApplicationController
  # The public pages every app serves without an account; config/routes/legal.rb
  # draws a route for each.
  PAGES = %w[privacy terms cookies safety rules].freeze

  # The day the privacy, terms and cookies pages last changed, once for every
  # locale: each locale used to hand-type its own copy of the date.
  UPDATED_ON = Date.new(2026, 8, 12)

  helper Shared::Safety
  helper Shared::Rules

  allow_unauthenticated_access only: :show if respond_to?(:allow_unauthenticated_access)

  def show
    @page = params[:page].to_s
    raise ActionController::RoutingError, "no such page" unless PAGES.include?(@page)

    render @page
  end
end
