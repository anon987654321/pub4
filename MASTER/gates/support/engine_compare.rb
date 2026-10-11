# frozen_string_literal: true

require "tmpdir"
require_relative "capture_engine"

module Deploy
  # The same surface in a second engine, compared with Chrome box by box. A
  # box that moves or resizes by more than the tolerance is a layout that only
  # looks right in one browser. Surfaces reached by a mapped host name are
  # skipped: only Chrome carries the host-resolver rules.
  module EngineCompare
    MAX_DIVERGENCES = 12

    module_function

    def tolerance = Integer(ENV.fetch("MASTER_VISUAL_ENGINE_TOLERANCE", "8"))

    # Boxes both engines laid out whose position or size differs by more than
    # the tolerance, largest first, plus the keys only one engine produced.
    def diff(reference, other, tolerance: self.tolerance)
      ours = index(reference)
      theirs = index(other)
      moved = (ours.keys & theirs.keys).filter_map do |key|
        a = ours.fetch(key)
        b = theirs.fetch(key)
        delta = %w[x y w h].to_h { |axis| [axis, b[axis].to_i - a[axis].to_i] }
        size = delta.values.map(&:abs).max
        { "key" => key, "delta" => delta, "size" => size } if size > tolerance
      end
      { "divergences" => moved.sort_by { |row| -row["size"] }.first(MAX_DIVERGENCES), "diverging" => moved.size,
        "compared" => (ours.keys & theirs.keys).size,
        "only_in_reference" => (ours.keys - theirs.keys).size, "only_in_engine" => (theirs.keys - ours.keys).size,
        "tolerance" => tolerance }
    end

    def index(geometry) = Array(geometry && geometry["rows"]).to_h { |row| [row["key"], row] }

    # One capture per extra engine for this surface, in the shape the visual
    # pass already carries. Engines that cannot open are recorded on
    # CaptureEngine.unavailable and yield nothing.
    def captures(cdp, surface, dir:, names: CaptureEngine.others, factory: nil)
      return [] if names.empty? || surface.host

      reference = reference_geometry(cdp, surface)
      names.filter_map do |name|
        engine = CaptureEngine.open(name, factory:)
        next unless engine

        begin
          capture(engine, surface, reference, dir:)
        rescue StandardError => e
          CaptureEngine.unavailable[name] = "#{e.class}: #{e.message[0, 100]}"
          nil
        ensure
          engine.close
        end
      end
    end

    def reference_geometry(cdp, surface)
      chrome = CaptureEngine::ChromeEngine.wrap(cdp)
      chrome.viewport(surface.width, surface.height, mobile: surface.width.to_i < 500)
      chrome.navigate(surface.url)
      chrome.geometry
    end

    def capture(engine, surface, reference, dir:)
      engine.viewport(surface.width, surface.height, mobile: surface.width.to_i < 500)
      engine.navigate(surface.url)
      geometry = engine.geometry
      result = diff(reference, geometry).merge("name" => engine.name)
      derived = derived_surface(surface, engine.name)
      shot = File.join(dir, "#{derived.id.to_s.gsub(/[^a-zA-Z0-9._-]+/, "_")}.png")
      engine.screenshot(shot)
      payload = { "elements" => [], "scroll_width" => geometry["scroll_width"], "client_width" => geometry["width"],
                  "composition" => { "state" => "engine", "engine" => engine.name, "base_surface" => surface.id,
                                     "trigger" => "#{engine.name} vs chrome" },
                  "engine" => result }
      { surface: derived, payload:, screenshot: shot, journeys: [], platform: {} }
    end

    def derived_surface(surface, name)
      GeometryProbe::Surface.new(
        app: surface.app, label: "#{surface.label}__engine_#{name}", host: surface.host, path: surface.path,
        viewport: surface.viewport, width: surface.width, height: surface.height, snapshot: false,
        port: surface.port, profile: surface.profile
      )
    end
  end
end
