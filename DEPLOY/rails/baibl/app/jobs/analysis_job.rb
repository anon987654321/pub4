# frozen_string_literal: true

class AnalysisJob < ApplicationJob
  queue_as :analysis

  def perform(verse_id)
    verse = Verse.find(verse_id)
    Shared::EventEmitter.call("baibl.analysis.started", verse_id: verse.id) if defined?(Shared::EventEmitter)

    # Hook AI linguistic/context analysis here. Keep output deterministic and reviewable:
    # verse -> analysis request -> Analysis upsert -> Turbo Stream update.

    Shared::EventEmitter.call("baibl.analysis.completed", verse_id: verse.id) if defined?(Shared::EventEmitter)
  rescue StandardError => e
    Shared::EventEmitter.call("baibl.analysis.failed", verse_id:, error: e.message) if defined?(Shared::EventEmitter)
    raise
  end
end
