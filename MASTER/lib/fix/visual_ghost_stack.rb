# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "set"

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
      GHOST_OPACITIES = [ 0.04, 0.06, 0.08, 0.12 ].freeze
      CURRENT_OPACITY = 1.0
      REGISTRATION_GRID_PX = 8
      MAX_GEOMETRY_MARKERS = 24

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
        { key:, history: frames, ghost:, drift: geometry_drift(frames, history), state: }
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

        html = File.join(@dir, "ghost-#{key}.html")
        png = File.join(@dir, "ghost-#{key}.png")
        File.write(html, stack_page(surface:, state:, frames:))
        screenshot_file(html, png, cdp:)
        {
          screenshot: png,
          diff: render_pair(surface:, state:, frames:, key:, cdp:),
          geometry: render_geometry(surface:, state:, frames:, key:, cdp:),
          grid: render_grid(surface:, state:, frames:, key:, cdp:),
          label: "#{surface.id} | #{state} | #{frames.length} aligned passes",
        }
      end

      def render_pair(surface:, state:, frames:, key:, cdp:)
        return nil if frames.length < 2

        html = File.join(@dir, "diff-#{key}.html")
        png = File.join(@dir, "diff-#{key}.png")
        previous, current = frames.last(2)
        File.write(html, diff_page(surface:, state:, current:, previous:))
        screenshot_file(html, png, cdp:)
        png
      end

      def screenshot_file(html, png, cdp:)
        cdp.viewport(1800, 1400, mobile: false)
        cdp.navigate("file://#{html}")
        cdp.screenshot(png, capture_beyond_viewport: true)
        png
      end

      def stack_page(surface:, state:, frames:)
        images = frames.each_with_index.map do |path, index|
          current = index == frames.length - 1
          opacity = current ? CURRENT_OPACITY : GHOST_OPACITIES.fetch([index, GHOST_OPACITIES.length - 1].min)
          encoded = Base64.strict_encode64(File.binread(path))
          label = current ? "current" : "pass #{File.basename(path, ".png").split("-pass-").last.to_i}"
          class_name = current ? "current" : "ghost"
          %(<img class="#{class_name}" src="data:image/png;base64,#{encoded}" alt="#{escape_html(label)}" style="opacity:#{opacity};">)
        end.join
        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>
          *{box-sizing:border-box}html,body{margin:0;background:#fff}
          body{font:16px/1.4 system-ui,sans-serif;padding:16px}
          header{margin:0 0 12px;font-weight:700}
          .stage{position:relative;display:inline-block;line-height:0}
          .stage img{position:absolute;inset:0;width:auto;height:auto;max-width:none}
          .stage img.current{position:relative}
          </style></head><body>
          <header>ghost stack · #{escape_html(surface.id)} · #{escape_html(state)}</header>
          <div class="stage">#{images}</div>
          </body></html>
        HTML
      end

      def render_geometry(surface:, state:, frames:, key:, cdp:)
        return nil if frames.length < 2

        previous_path, current_path = frames.last(2)
        previous = JSON.parse(File.read(json_for(previous_path, File.dirname(previous_path))))
        current = JSON.parse(File.read(json_for(current_path, File.dirname(current_path))))
        width, height = png_dimensions(current_path)
        html = File.join(@dir, "geometry-#{key}.html")
        png = File.join(@dir, "geometry-#{key}.png")
        File.write(
          html,
          geometry_page(surface:, state:, current:, previous:, width:, height:, image_path: current_path),
        )
        screenshot_file(html, png, cdp:)
        png
      rescue StandardError
        nil
      end

      def render_grid(surface:, state:, frames:, key:, cdp:)
        return nil if frames.empty?

        current = frames.last
        width, height = png_dimensions(current)
        html = File.join(@dir, "grid-#{key}.html")
        png = File.join(@dir, "grid-#{key}.png")
        File.write(html, grid_page(surface:, state:, current:, width:, height:, image_path: current))
        screenshot_file(html, png, cdp:)
        png
      rescue StandardError
        nil
      end

      def geometry_page(surface:, state:, current:, previous:, width:, height:, image_path:)
        before = Array(previous["elements"]).to_h { |element| [element["key"], element] }
        after = Array(current["elements"]).to_h { |element| [element["key"], element] }
        rows = (before.keys & after.keys).filter_map do |key|
          old = before[key]
          new = after[key]
          old_rect = old["frect"] || old["rect"] || {}
          new_rect = new["frect"] || new["rect"] || {}
          delta = %w[x y w h].to_h { |axis| [axis, new_rect[axis].to_f - old_rect[axis].to_f] }
          next if delta.values.all? { |value| value.abs <= DIFF_TOLERANCE_PX }

          {
            old: old_rect,
            new: new_rect,
            delta:
          }
        end.sort_by { |row| -row[:delta].values.sum { |value| value.abs } }.first(MAX_GEOMETRY_MARKERS)

        encoded = Base64.strict_encode64(File.binread(image_path))
        overlays = rows.each_with_index.map do |row, index|
          old = row[:old]
          new = row[:new]
          label_x = new.fetch("x").to_f + new.fetch("w").to_f + 6
          label_y = new.fetch("y").to_f + 12
          %(
            <rect x="#{old.fetch("x")}" y="#{old.fetch("y")}" width="#{old.fetch("w")}" height="#{old.fetch("h")}" fill="none" stroke="#a855f7" stroke-width="1"/>
            <rect x="#{new.fetch("x")}" y="#{new.fetch("y")}" width="#{new.fetch("w")}" height="#{new.fetch("h")}" fill="none" stroke="#06b6d4" stroke-width="1.5"/>
            <line x1="#{old.fetch("x")}" y1="#{old.fetch("y")}" x2="#{new.fetch("x")}" y2="#{new.fetch("y")}" stroke="#f59e0b" stroke-width="1"/>
            <text x="#{label_x}" y="#{label_y}" fill="#111" font-size="10">#{index + 1} Δx=#{row[:delta]["x"].round(1)} Δy=#{row[:delta]["y"].round(1)}</text>
          )
        end.join

        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>
          *{box-sizing:border-box}html,body{margin:0;background:#fff;color:#111}
          body{font:16px/1.4 system-ui,sans-serif;padding:16px}
          header{margin:0 0 12px;font-weight:700}
          .legend{margin:0 0 12px;font-size:13px}
          .stage{position:relative;display:inline-block;line-height:0}
          .stage img{display:block;position:relative;width:auto;height:auto;max-width:none}
          .stage svg{position:absolute;inset:0;pointer-events:none}
          </style></head><body>
          <header>geometry registration · #{escape_html(surface.id)} · #{escape_html(state)}</header>
          <p class="legend">purple = previous box · cyan = current box · amber = movement vector</p>
          <div class="stage">
            <img src="data:image/png;base64,#{encoded}" alt="current render">
            <svg width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" aria-hidden="true">#{overlays}</svg>
          </div>
          </body></html>
        HTML
      end

      def grid_page(surface:, state:, current:, width:, height:, image_path:)
        encoded = Base64.strict_encode64(File.binread(image_path))
        step = REGISTRATION_GRID_PX
        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>
          *{box-sizing:border-box}html,body{margin:0;background:#fff;color:#111}
          body{font:16px/1.4 system-ui,sans-serif;padding:16px}
          header{margin:0 0 12px;font-weight:700}
          .stage{position:relative;display:inline-block;line-height:0}
          .stage img{display:block;position:relative;width:auto;height:auto;max-width:none}
          .grid{position:absolute;inset:0;pointer-events:none;
            background-image:linear-gradient(to right,rgba(17,17,17,.12) 1px,transparent 1px),
                             linear-gradient(to bottom,rgba(17,17,17,.12) 1px,transparent 1px);
            background-size:#{step}px #{step}px}
          .vcenter,.hcenter{position:absolute;background:rgba(220,99,92,.8);pointer-events:none}
          .vcenter{top:0;bottom:0;width:1px;left:50%}
          .hcenter{left:0;right:0;height:1px;top:50%}
          </style></head><body>
          <header>registration grid · #{escape_html(surface.id)} · #{escape_html(state)} · #{step}px</header>
          <div class="stage">
            <img src="data:image/png;base64,#{encoded}" alt="current render">
            <div class="grid"></div><div class="vcenter"></div><div class="hcenter"></div>
          </div>
          </body></html>
        HTML
      end

      def png_dimensions(path)
        bytes = File.binread(path, 24)
        raise "not a PNG" unless bytes.start_with?("\x89PNG\r\n\x1a\n".b)

        [bytes.byteslice(16, 4).unpack1("N"), bytes.byteslice(20, 4).unpack1("N")]
      end

      def diff_page(surface:, state:, current:, previous:)
        current64 = Base64.strict_encode64(File.binread(current))
        previous64 = Base64.strict_encode64(File.binread(previous))
        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>
          *{box-sizing:border-box}html,body{margin:0;background:#808080}
          body{font:16px/1.4 system-ui,sans-serif;padding:16px}
          header{margin:0 0 12px;color:#fff;font-weight:700}
          .stage{position:relative;display:inline-block;line-height:0;background:#000}
          .stage img{position:absolute;inset:0;width:auto;height:auto;max-width:none}
          .stage img.base{position:relative}
          .stage img.diff{mix-blend-mode:difference}
          </style></head><body>
          <header>difference · #{escape_html(surface.id)} · #{escape_html(state)} · newer over older</header>
          <div class="stage">
            <img class="base" src="data:image/png;base64,#{current64}" alt="current render">
            <img class="diff" src="data:image/png;base64,#{previous64}" alt="previous render">
          </div>
          </body></html>
        HTML
      end

      # The elements that moved or retyped between the two newest frames, largest
      # first, then one structural row when elements appeared or disappeared.
      def geometry_drift(frames, history)
        return [] if frames.length < 2

        older, newer = frames.last(2)
        before = elements_of(json_for(older, history))
        after = elements_of(json_for(newer, history))
        changed = (before.keys & after.keys).filter_map { |key| element_drift(key, before[key], after[key]) }
        changed.sort_by { |row| -row["magnitude"] }.first(12) + structural_drift(before, after)
      rescue StandardError
        []
      end

      def elements_of(payload_path)
        Array(JSON.parse(File.read(payload_path))["elements"]).to_h { |element| [ element["key"], element ] }
      end

      def element_drift(key, old, new)
        old_rect = old["frect"] || old["rect"] || {}
        new_rect = new["frect"] || new["rect"] || {}
        delta = %w[x y w h].to_h { |axis| [axis, new_rect[axis].to_f - old_rect[axis].to_f] }
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

      def json_for(png, history)
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

      def escape_html(value)
        value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
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
