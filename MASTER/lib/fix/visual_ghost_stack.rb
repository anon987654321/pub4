# frozen_string_literal: true

require "fileutils"
require "json"
require "set"
require_relative "visual_ghost_pages"

module Master
  module Fix
    # Persistent visual evidence for /fix: never replace a clean render with a
    # screenshot memory. Keep a short history for each surface/state, then make
    # the drift visible by stacking aligned frames at low opacity and by a
    # difference view of the newest two frames.
    #
    # Screenshots and payloads live under MASTER/.master/, which is ignored and
    # therefore cannot become source or a golden baseline. The history is small,
    # bounded, and keyed by surface + composition state so unrelated pages never
    # get blended together.
    class VisualGhostStack
      HISTORY_LIMIT = 5
      DIFF_TOLERANCE_PX = 0.5
      GHOST_OPACITIES = [ 0.04, 0.06, 0.09, 0.12 ].freeze
      CURRENT_OPACITY = 0.72
      REGISTRATION_GRID_PX = 8
      MAX_GEOMETRY_MARKERS = 24
      FOCUS_SCALE = 2
      FOCUS_PADDING_PX = 24
      FOCUS_MIN_SIZE_PX = 160
      FOCUS_MAX_SIZE_PX = 480

      def initialize(root:, dir:)
        @root = root
        @dir = dir
        @run_id = ENV["MASTER_VISUAL_RUN_ID"].to_s.strip
        @run_id = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N") if @run_id.empty?
      end

      def capture(capture, pass:, cdp:)
        state = state_of(capture)
        surface = capture.fetch(:surface)
        key = safe_slug("#{surface.id}__#{state}")
        history = history_dir(key)
        frames = record_frame(history, capture, pass)
        ghost = render_stack(surface:, state:, frames:, key:, cdp:)
        { key:, history: frames, ghost:, drift: geometry_drift(frames), state: }
      rescue StandardError => e
        { key: key, history: [], ghost: nil, drift: [], state: state, error: "#{e.class}: #{e.message}" }
      end

      private

      def state_of(capture)
        state = capture.dig(:payload, "composition", "state").to_s
        state.empty? ? "resting" : state
      end

      def history_dir(key)
        File.join(@root, "MASTER", ".master", "visual_evidence", key).tap { |dir| FileUtils.mkdir_p(dir) }
      end

      # Stores this pass's screenshot and payload beside the earlier ones and
      # returns the newest HISTORY_LIMIT frames, oldest first.
      def record_frame(history, capture, pass)
        stem = "#{safe_slug(@run_id)}-pass-#{format("%06d", pass.to_i)}"
        FileUtils.cp(capture.fetch(:screenshot), File.join(history, "#{stem}.png"))
        File.write(File.join(history, "#{stem}.json"), JSON.pretty_generate(capture.fetch(:payload)))
        prune(history)
        Dir.glob(File.join(history, "*-pass-*.png")).sort.last(HISTORY_LIMIT)
      end

      def render_stack(surface:, state:, frames:, key:, cdp:)
        return nil if frames.empty?

        page = VisualGhostPages.stack(surface:, state:, frames:, ghost_opacities: GHOST_OPACITIES, current_opacity: CURRENT_OPACITY)
        {
          screenshot: render_page("ghost", key, page, cdp:),
          diff: render_pair(surface:, state:, frames:, key:, cdp:),
          geometry: render_geometry(surface:, state:, frames:, key:, cdp:),
          grid: render_grid(surface:, state:, frames:, key:, cdp:),
          focus: render_focus(surface:, state:, frames:, key:, cdp:),
          label: "#{surface.id} | #{state} | #{frames.length} aligned passes",
        }
      end

      def render_pair(surface:, state:, frames:, key:, cdp:)
        return nil if frames.length < 2

        previous, current = frames.last(2)
        render_page("diff", key, VisualGhostPages.diff(surface:, state:, current:, previous:), cdp:)
      end

      # Boxes of the newest frame against the previous one, largest move first.
      def render_geometry(surface:, state:, frames:, key:, cdp:)
        return nil if frames.length < 2

        previous_path, current_path = frames.last(2)
        rows = moved_rects(previous_path, current_path).first(MAX_GEOMETRY_MARKERS)
        width, height = png_dimensions(current_path)
        page = VisualGhostPages.geometry(surface:, state:, rows:, width:, height:, image_path: current_path)
        render_page("geometry", key, page, cdp:)
      rescue StandardError
        nil
      end

      # The element that moved most, cropped and enlarged with the previous frame under it.
      def render_focus(surface:, state:, frames:, key:, cdp:)
        return nil if frames.length < 2

        previous_path, current_path = frames.last(2)
        focus = moved_rects(previous_path, current_path).first
        return nil unless focus

        crop = focus_crop(focus, *png_dimensions(current_path))
        page = VisualGhostPages.focus(surface:, state:, previous_path:, current_path:, crop:)
        render_page("focus", key, page, cdp:)
      rescue StandardError
        nil
      end

      def focus_crop(focus, width, height)
        rect = focus[:new]
        w = (rect["w"].to_f + FOCUS_PADDING_PX * 2).clamp(FOCUS_MIN_SIZE_PX, FOCUS_MAX_SIZE_PX)
        h = (rect["h"].to_f + FOCUS_PADDING_PX * 2).clamp(FOCUS_MIN_SIZE_PX, FOCUS_MAX_SIZE_PX)
        x = (rect["x"].to_f + rect["w"].to_f / 2.0 - w / 2.0).clamp(0, [width - w, 0].max)
        y = (rect["y"].to_f + rect["h"].to_f / 2.0 - h / 2.0).clamp(0, [height - h, 0].max)
        { x:, y:, w:, h:, scale: FOCUS_SCALE, label: "#{focus[:key]} · Δ #{focus[:magnitude].round(1)}px" }
      end

      def render_grid(surface:, state:, frames:, key:, cdp:)
        return nil if frames.empty?

        page = VisualGhostPages.grid(surface:, state:, image_path: frames.last, step: REGISTRATION_GRID_PX)
        render_page("grid", key, page, cdp:)
      rescue StandardError
        nil
      end

      def render_page(kind, key, page, cdp:)
        html = File.join(@dir, "#{kind}-#{key}.html")
        png = File.join(@dir, "#{kind}-#{key}.png")
        File.write(html, page)
        cdp.viewport(1800, 1400, mobile: false)
        cdp.navigate("file://#{html}")
        cdp.screenshot(png, capture_beyond_viewport: true)
        png
      end

      # Stable elements whose box moved past the tolerance between the two frames,
      # as { key:, old:, new:, delta:, magnitude: }, largest move first.
      def moved_rects(previous_path, current_path)
        before = elements_of(json_for(previous_path))
        after = elements_of(json_for(current_path))
        (before.keys & after.keys).filter_map do |key|
          old_rect, new_rect, delta = rect_delta(before[key], after[key])
          next if delta.values.all? { |value| value.abs <= DIFF_TOLERANCE_PX }

          { key:, old: old_rect, new: new_rect, delta:, magnitude: delta.values.sum(&:abs) }
        end.sort_by { |row| -row[:magnitude] }
      end

      def rect_delta(old, new)
        old_rect = old["frect"] || old["rect"] || {}
        new_rect = new["frect"] || new["rect"] || {}
        [old_rect, new_rect, %w[x y w h].to_h { |axis| [axis, new_rect[axis].to_f - old_rect[axis].to_f] }]
      end

      def png_dimensions(path)
        bytes = File.binread(path, 24)
        raise "not a PNG" unless bytes.start_with?("\x89PNG\r\n\x1a\n".b)

        [bytes.byteslice(16, 4).unpack1("N"), bytes.byteslice(20, 4).unpack1("N")]
      end

      # The elements that moved or retyped between the two newest frames, largest
      # first, then one structural row when elements appeared or disappeared.
      def geometry_drift(frames)
        return [] if frames.length < 2

        older, newer = frames.last(2)
        before = elements_of(json_for(older))
        after = elements_of(json_for(newer))
        changed = (before.keys & after.keys).filter_map { |key| element_drift(key, before[key], after[key]) }
        changed.sort_by { |row| -row["magnitude"] }.first(12) + structural_drift(before, after)
      rescue StandardError
        []
      end

      def elements_of(payload_path)
        Array(JSON.parse(File.read(payload_path))["elements"]).to_h { |element| [ element["key"], element ] }
      end

      def element_drift(key, old, new)
        _old_rect, _new_rect, delta = rect_delta(old, new)
        type_delta = {
          "font_size" => new["font_size"].to_f - old["font_size"].to_f,
          "line_height" => new["line_height"].to_f - old["line_height"].to_f,
        }.reject { |_axis, value| value.abs <= DIFF_TOLERANCE_PX }
        moved = delta.reject { |_axis, value| value.abs <= DIFF_TOLERANCE_PX }
        return if moved.empty? && type_delta.empty?

        magnitude = delta.values.sum(&:abs) + type_delta.values.sum(&:abs)
        { "key" => key, "text" => new["text"], "delta" => moved, "type" => type_delta, "magnitude" => magnitude.round(2) }
      end

      def structural_drift(before, after)
        missing = before.keys - after.keys
        added = after.keys - before.keys
        return [] if missing.empty? && added.empty?

        [{ "structural" => { "missing" => missing.size, "added" => added.size } }]
      end

      def json_for(png)
        png.sub(/\.png\z/, ".json")
      end

      def prune(history)
        pngs = Dir.glob(File.join(history, "*-pass-*.png")).sort
        keep = pngs.last(HISTORY_LIMIT)
        (pngs - keep).each { |path| File.delete(path) }
        keep_stems = keep.map { |shot| File.basename(shot, ".png") }.to_set
        Dir.glob(File.join(history, "*-pass-*.json")).sort.each do |path|
          File.delete(path) unless keep_stems.include?(File.basename(path, ".json"))
        end
      end

      def safe_slug(value)
        value.to_s.gsub(/[^a-zA-Z0-9._-]+/, "_")
      end

      def repo_root
        File.expand_path("../..", @root)
      end
    end
  end
end
