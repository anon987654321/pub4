# frozen_string_literal: true

module Shared
  # Records a click on a link that leaves the site, then answers 204.
  #
  # A beacon rather than a redirect, for two reasons that both matter more than
  # the extra request:
  #
  #   1. A /out?url=… redirect is an open redirect unless every target is signed
  #      or allowlisted, and an open redirect on a social site is a phishing
  #      primitive. This endpoint never receives a URL it will send anyone to.
  #   2. TradeDoubler's Link Converter script rewrites outbound anchors in the
  #      browser. Pointing the anchor at our own host instead would hide the
  #      merchant URL from it and take attribution to zero — measurement that
  #      destroys the thing it measures.
  #
  # So the anchor keeps the merchant URL, the script still rewrites it, and this
  # records that it was clicked.
  class OutboundClicksController < ApplicationController
    # No allow_unauthenticated_access: guests already get a soft Current.user in
    # the apps with a guest column, where that macro is a documented no-op.
    skip_before_action :verify_authenticity_token, only: :create

    # sendBeacon cannot set headers, so it arrives without a CSRF token. That is
    # why forgery protection is skipped, and why this action writes nothing a
    # forged request could abuse: no redirect, no user-controlled response, and a
    # rate limit so a script cannot inflate the numbers it is here to report.
    rate_limit to: 60, within: 1.minute, only: :create if respond_to?(:rate_limit)

    def create
      Shared::OutboundClick.record(
        app: app_name,
        url: params[:url],
        surface: params[:surface],
        merchant: params[:merchant],
        epi: params[:epi],
        user: Current.try(:user),
      )
      head :no_content
    rescue StandardError => e
      # A failed measurement must never be visible to the visitor: they clicked a
      # link and it is already opening. Swallow, but say so in the log.
      Rails.logger.warn("[outbound_click] #{e.class}: #{e.message}")
      head :no_content
    end

    private

    def app_name
      Rails.application.class.module_parent_name.to_s.downcase
    end
  end
end
