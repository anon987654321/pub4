# frozen_string_literal: true

class CitiesController < ApplicationController
  def index
    @cities = Brgen::DomainRegistry::ENTRIES.map { |e| [e.city, e.domain] }.sort_by(&:first)
  end

  def update
    domain = params[:domain].to_s
    entry = Brgen::DomainRegistry::ENTRIES_BY_DOMAIN[domain]
    unless entry
      redirect_back fallback_location: root_path, alert: "Unknown city"
      return
    end

    session[:city_override_domain] = entry.domain
    session[:city_override_city] = entry.city

    Current.city = entry.city
    Current.domain = entry.domain
    Current.country = entry.country
    Current.currency = entry.currency
    Current.locale = entry.locale
    I18n.locale = entry.locale

    redirect_back fallback_location: root_path, notice: "Switched to #{entry.city}"
  end
end