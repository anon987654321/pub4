# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method
  include Shared::CacheableShow

  turbo_refreshes_with :morph

  before_action :set_domain_context
  before_action :ensure_onboarding_complete, if: :authenticated?

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def ensure_onboarding_complete
    return unless Current.user.respond_to?(:onboarding_completed_at)
    return if controller_name.in?(%w[onboardings sessions passwords])
    return if Current.user.onboarding_completed_at.present?

    redirect_to onboarding_path
  end

  def set_domain_context
    result = Brgen::DomainRegistry.resolve(request.host)
    entry = result.entry

    if session[:city_override_domain].present?
      override = Brgen::DomainRegistry::ENTRIES_BY_DOMAIN[session[:city_override_domain]]
      entry = override if override
    end

    Current.city = entry.city
    Current.country = entry.country
    Current.currency = entry.currency
    Current.domain = entry.domain
    Current.locale = entry.locale
    Current.subapp = result.subapp

    I18n.locale = entry.locale
  rescue Brgen::DomainRegistry::UnknownHost, Brgen::DomainRegistry::UnknownSubdomain
    render plain: "Unknown host", status: :not_found
  end
end
