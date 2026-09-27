# frozen_string_literal: true

module Shared
  # Session-backed autosave for in-progress forms: the composer PUTs whatever it
  # has, keyed by form id, and gets it back on the next render.
  module DraftsActions
    extend ActiveSupport::Concern

    MAX_BYTES = 3_000
    SENSITIVE_PARTS = %w[
      password password_confirmation token secret api_key private_key otp authenticity
    ].freeze

    def update
      draft = draft_params
      return head :content_too_large if JSON.generate(draft).bytesize > MAX_BYTES

      session[:drafts] ||= {}
      session[:drafts][params[:id].to_s] = draft
      head :no_content
    end

    private

    # Autosave fields are intentionally opaque to the shared endpoint, but
    # credential-shaped names are never useful as drafts and must not reach the
    # cookie session. The browser still keeps the complete local IndexedDB copy.
    def draft_params
      sanitize_draft(params.to_unsafe_h.except("controller", "action", "id", "authenticity_token", "_method"))
    end

    def sanitize_draft(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), clean|
          next if sensitive_draft_key?(key)

          clean[key] = sanitize_draft(child)
        end
      when Array
        value.map { |child| sanitize_draft(child) }
      else
        value
      end
    end

    def sensitive_draft_key?(key)
      key.to_s.scan(/[a-z0-9]+/i).any? { |part| SENSITIVE_PARTS.include?(part.downcase) }
    end
  end
end
