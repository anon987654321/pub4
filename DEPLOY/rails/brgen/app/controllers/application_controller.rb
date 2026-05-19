# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method

  before_action :set_domain_context

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def set_domain_context
    result = Brgen::DomainRegistry.resolve(request.host)

    Current.city = result.entry.city
    Current.country = result.entry.country
    Current.currency = result.entry.currency
    Current.domain = result.entry.domain
    Current.locale = result.entry.locale
    Current.subapp = result.subapp

    I18n.locale = result.entry.locale
  rescue Brgen::DomainRegistry::UnknownHost, Brgen::DomainRegistry::UnknownSubdomain
    render plain: "Unknown host", status: :not_found
  end
end
