# frozen_string_literal: true

class ActivityEventRecorder
  def self.call(actor:, event_name:, object:, source_vertical:, locality: nil, visibility: "public", metadata: {})
    ActivityEvent.create!(
      actor: actor,
      event_name: event_name,
      object_type: object.class.name,
      object_id: object.id,
      source_vertical: source_vertical,
      locality: locality,
      visibility: visibility,
      metadata: metadata
    )
  end
end
