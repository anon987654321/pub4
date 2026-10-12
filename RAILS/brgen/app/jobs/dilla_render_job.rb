# frozen_string_literal: true

class DillaRenderJob < ApplicationJob
  queue_as :bulk

  def perform(sketch_id, publish: true)
    sketch = Playlist::DillaSketch.find_by(id: sketch_id)
    return unless sketch

    sketch.update!(render_status: "rendering", render_error: nil)
    unless Shared::DillaProcessor.available?
      sketch.update!(render_status: "failed", render_error: "dilla engine not found (DeployPaths)")
      return
    end

    ok = Shared::DillaProcessor.attach_to_record!(sketch, attachment_name: :render)
    unless ok
      sketch.update!(render_status: "failed", render_error: "render failed or empty output")
      return
    end

    track = publish ? sketch.publish_as_track! : nil
    sketch.update!(
      render_status: "ready",
      rendered_at: Time.current,
      track: track
    )
  rescue StandardError => e
    sketch&.update(render_status: "failed", render_error: "#{e.class}: #{e.message}")
    raise
  end
end
