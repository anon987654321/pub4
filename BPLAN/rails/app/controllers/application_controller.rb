# frozen_string_literal: true

class ApplicationController < ActionController::Base
  helper_method :catalog, :show_pay_buttons?, :not_found, :bolig_asap_pending?, :bolig_portal_sept_pending?

  def bolig_asap_pending?
    catalog.bolig_asap_pending?
  end

  def bolig_portal_sept_pending?
    catalog.bolig_portal_sept_pending?
  end

  private

  def catalog
    Bplan::Catalog
  end

  def show_pay_buttons?
    value = ENV.fetch("BPLAN_SHOW_PAY", "1")
    %w[1 true yes on].include?(value.to_s.downcase)
  end

  def not_found
    raise ActionController::RoutingError, "Not Found"
  end
end