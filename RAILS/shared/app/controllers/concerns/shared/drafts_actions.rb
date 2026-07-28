# frozen_string_literal: true

module Shared
  # Session-backed autosave for in-progress forms: the composer PUTs whatever it
  # has, keyed by form id, and gets it back on the next render.
  module DraftsActions
    extend ActiveSupport::Concern

    def update
      session[:drafts] ||= {}
      session[:drafts][params[:id].to_s] = draft_params
      head :no_content
    end

    private

    # to_unsafe_h because the draft is opaque — the point is to store whatever
    # the form had, and it is read back into the same form, never mass-assigned.
    def draft_params
      params.to_unsafe_h.except("controller", "action", "id", "authenticity_token", "_method")
    end
  end
end
