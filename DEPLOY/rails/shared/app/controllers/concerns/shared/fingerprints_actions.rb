# frozen_string_literal: true

module Shared
  module FingerprintsActions
    extend ActiveSupport::Concern

    def create
      fingerprint = params[:fingerprint].to_s.downcase
      return head :bad_request unless fingerprint.match?(/\A[0-9a-f]{64}\z/)

      cookies.signed.permanent[:browser_fingerprint] = {
        value: fingerprint,
        httponly: true,
        same_site: :lax
      }
      head :no_content
    end
  end
end