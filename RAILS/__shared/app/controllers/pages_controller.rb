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

  # A signed-out reader revalidates rather than caching for a day. A page held
  # for a day would keep the language, navigation and stylesheet address it was
  # served with after a deploy, and a CSRF token from a session that has since
  # ended. The ETag names everything the page is built from, so an unchanged
  # page is a 304 with no body and a changed one is sent whole. The default
  # Cache-Control fresh_when sends is private, max-age=0, must-revalidate:
  # nothing shared between people stores it. A signed-in reader's chrome
  # carries counts and links this key does not name, so it is always rendered.
  def show
    @page = params[:page].to_s
    raise ActionController::RoutingError, "no such page" unless PAGES.include?(@page)

    fresh_when(etag: page_etag, template: "pages/#{@page}") unless authenticated? || flash.any?
    render @page unless performed?
  end

  private

  def page_etag
    # form_authenticity_token stores the session's CSRF secret on a first visit, so
    # the key names it from the first response on: a page kept from a session
    # that has since ended carries a token that no longer verifies.
    form_authenticity_token
    [ @page, I18n.locale, request.host, UPDATED_ON, session[:_csrf_token], Current.user&.cache_key_with_version,
      helpers.asset_path("application.css"), Rails.application.try(:revision) ]
  end
end
