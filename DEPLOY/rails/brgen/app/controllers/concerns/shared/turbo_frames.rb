# frozen_string_literal: true
# AN401: Turbo Frames for list indexes

module Shared
  module TurboFrames
    extend ActiveSupport::Concern

    private

    def turbo_frame_list_id(resource_name = controller_name)
      resource_name.to_s.singularize.pluralize
    end

    def render_turbo_frame_list(collection:, partial:, locals: {})
      render partial: "shared/turbo_frame_list",
             locals: { frame_id: turbo_frame_list_id, collection: collection, partial: partial, locals: locals }
    end
  end
end