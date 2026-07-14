# frozen_string_literal: true

module Api
  class LegatsController < ApplicationController
    def index
      track = params[:track].presence
      legats = catalog.legats_filtered(track: track).map do |entry|
        entry.slice("id", "funder", "track", "deadline", "project", "draft", "sendable").merge(
          "sendable_effective" => catalog.sendable?(entry),
        )
      end
      render json: legats
    end
  end
end