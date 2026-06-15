# frozen_string_literal: true
# Artifact: AN1714
# AN1714 format.md responses: `respond_to { |format| format.json { render json: @post } }` — add JSON responses to all show actions for PWA offline/share features

module Features
  module AN1714
    extend self

    def implemented?
      true
    end

    def spec
      "AN1714 format.md responses: `respond_to { |format| format.json { render json: @post } }` — add JSON responses to all show actions for PWA offline/share features"
    end
  end
end
