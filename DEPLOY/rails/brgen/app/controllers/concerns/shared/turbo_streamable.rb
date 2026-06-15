# frozen_string_literal: true
# AN402/AN403: Turbo Stream broadcasts and form responses

module Shared
  module TurboStreamable
    extend ActiveSupport::Concern

    private

    def respond_with_turbo_form(record, partial:, stream_target:)
      if record.errors.any?
        render turbo_stream: turbo_stream.replace(stream_target, partial: partial, locals: { record: record })
      else
        render turbo_stream: turbo_stream.replace(stream_target, partial: partial, locals: { record: record })
      end
    end

    def broadcast_model_event(record, action:)
      return unless record.class.respond_to?(:broadcast_#{action}_to)

      record.public_send("broadcast_#{action}_to", record.broadcast_channel, target: dom_id(record))
    rescue NoMethodError
      nil
    end
  end
end