# frozen_string_literal: true

# Static legal + info pages served on every city domain (privacy, terms, cookies).
# Public by design — a privacy policy behind a login helps no one, and TradeDoubler
# / GDPR both require these to be reachable without an account. Content lives in the
# views (localised nb/en) rather than the database; there is nothing to persist.
class PagesController < ApplicationController
  PAGES = %w[privacy terms cookies].freeze

  def show
    @page = params[:page].to_s
    raise ActionController::RoutingError, "no such page" unless PAGES.include?(@page)

    render @page
  end
end
