# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"

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
      GHOST_OPACITIES = [ 0.05, 0.08, 0.12, 0.18, 0.32 ].freeze

      def initialize(root:, dir:)
        @root = root
        @dir = dir
      end

      def capture(capture, pass:)
        state = capture.dig(:payload, "composition", "state").to_s\n        state = "resting" if state.empty?
        surface = capture.fetch(:surface)
        key = safe_slug("#{surface.id}__#{state}")
        history = File.join(@root, "MASTER", ".master", "visual_evidence", key)
        FileUtils.mkdir_p(history)

        shot = File.join(history, format("pass-%06d.png", pass.to_i))
        payload_path = File.join(history, format("pass-%06d.json", pass.to_i))
        FileUtils.cp(capture.fetch(:screenshot), shot)
        File.write(payload_path, JSON.pretty_generate(capture.fetch(:payload)))
        prune(history)

        frames = Dir.glob(File.join(history, "pass-*.png")).sort.last(HISTORY_LIMIT)
        ghost = render_stack(surface:, state:, frames:, key:)
        drift = geometry_drift(frames, history)
        {
          key:,
          history: frames,
          ghost:,
          drift:,
          state:,
        }
      rescue StandardError => e
        { key: key, history: [], ghost: nil, drift: [], state: state, error: "#{e.class}: #{e.message}" }
      end

      private

      def render_stack(surface:, state:, frames:, key:)
        return nil if frames.empty?

        html = File.join(@dir, "ghost-#{key}.html")
        png = File.join(@dir, "ghost-#{key}.png")
        File.write(html, stack_page(surface:, state:, frames:))
        screenshot_file(html, png)
        {
          screenshot: png,
          diff: render_pair(surface:, state:, frames:, key:),
          label: "#{surface.id} | #{state} | #{frames.length} aligned passes",
        }
      end

      def render_pair(surface:, state:, frames:, key:)
        return nil if frames.length < 2

        html = File.join(@dir, "diff-#{key}.html")
        png = File.join(@dir, "diff-#{key}.png")
        current, previous = frames.last(2)
        File.write(html, diff_page(surface:, state:, current:, previous:))
        screenshot_file(html, png)
        png
      end

      def screenshot_file(html, png)
        Deploy::GeometryProbe.with_browser(root: repo_root, warm: []) do |cdp|
          cdp.viewport(1800, 1400, mobile: false)
          cdp.navigate("file://#{html}")
          cdp.screenshot(png, capture_beyond_viewport: true)
        end
        png
      end

      def stack_page(surface:, state:, frames:)
        images = frames.each_with_index.map do |path, index|
          opacity = GHOST_OPACITIES.fetch([index, GHOST_OPACITIES.length - 1].min)
          encoded = Base64.strict_encode64(File.binread(path))
          label = "pass #{File.basename(path, ".png").delete_prefix("pass-").to_i}"
          %(<img src="data:image/png;base64,#{encoded}" alt="#{escape_html(label)}" style="opacity:#{opacity};">)
        end.join
        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>
          *{box-sizing:border-box}html,body{margin:0;background:#fff}
          body{font:16px/1.4 system-ui,sans-serif;padding:16px}
          header{margin:0 0 12px;font-weight:700}
          .stage{position:relative;display:inline-block;line-height:0}
          .stage img{position:absolute;inset:0;width:auto;height:auto;max-width:none}
          .stage img:last-child{position:relative}
          </style></head><body>
          <header>ghost stack · #{escape_html(surface.id)} · #{escape_html(state)}</header>
          <div class="stage">#{images}</div>
          </body></html>
        HTML
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

      def geometry_drift(frames, history)
        return [] if frames.length < 2

        current_path, previous_path = frames.last(2).map { |path| json_for(path, history) }
        current = JSON.parse(File.read(current_path))
        previous = JSON.parse(File.read(previous_path))
        before = Array(previous["elements"]).to_h { |element| [ element["key"], element ] }
        after = Array(current["elements"]).to_h { |element| [ element["key"], element ] }

        changed = (before.keys & after.keys).filter_map do |key|
          old = before[key]
          new = after[key]
          old_rect = old["frect"] || old["rect"] || {}
          new_rect = new["frect"] || new["rect"] || {}
          delta = %w[x y w h].to_h do |axis|
            [axis, new_rect[axis].to_f - old_rect[axis].to_f]
          end
          type_delta = {
            "font_size" => new["font_size"].to_f - old["font_size"].to_f,
            "line_height" => new["line_height"].to_f - old["line_height"].to_f,
          }.reject { |_axis, value| value.abs <= DIFF_TOLERANCE_PX }
          next if delta.values.all? { |value| value.abs <= DIFF_TOLERANCE_PX } && type_delta.empty?

          magnitude = delta.values.sum { |value| value.abs } + type_delta.values.sum { |value| value.abs }
          {
            "key" => key,
            "text" => new["text"],
            "delta" => delta.reject { |_axis, value| value.abs <= DIFF_TOLERANCE_PX },
            "type" => type_delta,
            "magnitude" => magnitude.round(2),
          }
        end.sort_by { |row| -row["magnitude"] }.first(12)

        missing = before.keys - after.keys
        added = after.keys - before.keys
        changed + [
          { "structural" => { "missing" => missing.size, "added" => added.size } }
        ]
      rescue StandardError
        []
      end

      def json_for(png, history)
        png.sub(/\.png\z/, ".json")
      end

      def prune(history)
        pngs = Dir.glob(File.join(history, "pass-*.png")).sort
        keep = pngs.last(HISTORY_LIMIT)
        (pngs - keep).each { |path| File.delete(path) }
        Dir.glob(File.join(history, "pass-*.json")).sort.each do |path|
          pass = File.basename(path)[/pass-(\d+)\.json\z/, 1].to_i
          File.delete(path) unless keep.any? { |shot| File.basename(shot).include?(format("pass-%06d", pass)) }
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
