# frozen_string_literal: true

module Shared
  # Consent state for anything that sets a non-essential cookie or calls a
  # third party — currently advertising, and whatever analytics arrives later.
  #
  # There is no Consent Management Platform in this app yet, and every brgen
  # visitor is in the EEA, so the only honest answer today is "no". This method
  # exists so the ad surfaces can be built and placed against a real gate
  # rather than a TODO, and so wiring a CMP later is one method body rather
  # than a hunt through views.
  #
  # When a CMP lands it must set a durable, auditable signal — the TCF consent
  # string, not a homegrown boolean — and this should read that. Returning true
  # from a plain cookie the site sets itself would satisfy the code and not the
  # regulation.
  module ConsentHelper
    ADVERTISING_PURPOSE = "advertising"

    def advertising_consent?
      return false unless respond_to?(:cookies)

      consent_signal.present? && consent_signal.include?(ADVERTISING_PURPOSE)
    end

    private

    def consent_signal
      cookies[:pub4_consent].to_s
    end
  end
end
