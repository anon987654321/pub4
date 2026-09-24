# frozen_string_literal: true

require "base64"

module Master
  module Fix
    # The HTML pages VisualGhostStack screenshots: the ghost stack itself, the
    # difference view, the focus crop, the geometry registration and the grid.
    # Each is a self-contained document of inlined PNGs, so the browser needs no
    # file access beyond the page and nothing here reads the history on disk.
    module VisualGhostPages
      BASE_CSS = "*{box-sizing:border-box}html,body{margin:0;background:#fff;color:#111}" \
                 "body{font:16px/1.4 system-ui,sans-serif;padding:16px}header{margin:0 0 12px;font-weight:700}"
      LAYER_CSS = ".stage{position:relative;display:inline-block;line-height:0}" \
                  ".stage img{position:absolute;inset:0;width:auto;height:auto;max-width:none}"
      BASE_IMAGE_CSS = ".stage{position:relative;display:inline-block;line-height:0}" \
                       ".stage img{display:block;position:relative;width:auto;height:auto;max-width:none}"

      module_function

      def stack(surface:, state:, frames:, ghost_opacities:, current_opacity:)
        images = frames.each_with_index.map do |path, index|
          current = index == frames.length - 1
          opacity = current ? current_opacity : ghost_opacities.fetch([index, ghost_opacities.length - 1].min)
          label = current ? "current" : "pass #{File.basename(path, ".png").split("-pass-").last.to_i}"
          class_name = current ? "current" : "ghost"
          %(<img class="#{class_name}" src="#{data_uri(path)}" alt="#{escape_html(label)}" style="opacity:#{opacity};">)
        end.join
        document("#{LAYER_CSS}.stage img.current{position:relative}",
                 "ghost stack · #{escape_html(surface.id)} · #{escape_html(state)}",
                 %(<div class="stage">#{images}</div>))
      end

      def diff(surface:, state:, current:, previous:)
        css = "html,body{background:#808080}header{color:#fff}#{LAYER_CSS}.stage{background:#000}" \
              ".stage img.base{position:relative}.stage img.diff{mix-blend-mode:difference}"
        document(css, "difference · #{escape_html(surface.id)} · #{escape_html(state)} · newer over older", <<~HTML)
          <div class="stage">
            <img class="base" src="#{data_uri(current)}" alt="current render">
            <img class="diff" src="#{data_uri(previous)}" alt="previous render">
          </div>
        HTML
      end

      # crop: { x:, y:, w:, h:, scale:, label: } in the current render's pixels.
      def focus(surface:, state:, previous_path:, current_path:, crop:)
        scale = crop[:scale]
        css = "p{margin:0 0 12px;color:#555;font-size:13px}" \
              ".stage{position:relative;width:#{(crop[:w] * scale).round}px;height:#{(crop[:h] * scale).round}px;" \
              "overflow:hidden;border:1px solid #bbb;background:#fff}" \
              ".stage img{position:absolute;width:auto;height:auto;max-width:none;" \
              "left:-#{(crop[:x] * scale).round}px;top:-#{(crop[:y] * scale).round}px}" \
              ".stage img.previous{opacity:.42;mix-blend-mode:multiply}.stage img.current{opacity:.72}"
        document(css, "focus registration · #{escape_html(surface.id)} · #{escape_html(state)}", <<~HTML)
          <p>#{escape_html(crop[:label])} · current over previous at #{scale}×</p>
          <div class="stage">
            <img class="previous" src="#{data_uri(previous_path)}" alt="previous render focus">
            <img class="current" src="#{data_uri(current_path)}" alt="current render focus">
          </div>
        HTML
      end

      # rows: [{ old:, new:, delta: }] with rects as "x"/"y"/"w"/"h" hashes.
      def geometry(surface:, state:, rows:, width:, height:, image_path:)
        overlays = rows.each_with_index.map { |row, index| geometry_marker(row, index) }.join
        css = ".legend{margin:0 0 12px;font-size:13px}#{BASE_IMAGE_CSS}.stage svg{position:absolute;inset:0;pointer-events:none}"
        document(css, "geometry registration · #{escape_html(surface.id)} · #{escape_html(state)}", <<~HTML)
          <p class="legend">purple = previous box · cyan = current box · amber = movement vector</p>
          <div class="stage">
            <img src="#{data_uri(image_path)}" alt="current render">
            <svg width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" aria-hidden="true">#{overlays}</svg>
          </div>
        HTML
      end

      def geometry_marker(row, index)
        old = row[:old]
        new = row[:new]
        label_x = new.fetch("x").to_f + new.fetch("w").to_f + 6
        label_y = new.fetch("y").to_f + 12
        %(<rect x="#{old.fetch("x")}" y="#{old.fetch("y")}" width="#{old.fetch("w")}" height="#{old.fetch("h")}" fill="none" stroke="#a855f7" stroke-width="1"/>) +
          %(<rect x="#{new.fetch("x")}" y="#{new.fetch("y")}" width="#{new.fetch("w")}" height="#{new.fetch("h")}" fill="none" stroke="#06b6d4" stroke-width="1.5"/>) +
          %(<line x1="#{old.fetch("x")}" y1="#{old.fetch("y")}" x2="#{new.fetch("x")}" y2="#{new.fetch("y")}" stroke="#f59e0b" stroke-width="1"/>) +
          %(<text x="#{label_x}" y="#{label_y}" fill="#111" font-size="10">#{index + 1} Δx=#{row[:delta]["x"].round(1)} Δy=#{row[:delta]["y"].round(1)}</text>)
      end

      def squint(surface:, state:, image_path:, blur_px:)
        css = "#{BASE_IMAGE_CSS}.stage{overflow:visible}"               ".stage img{filter:grayscale(1) blur(#{blur_px}px);transform:scale(1.01)}"
        document(css, "squint composition · #{escape_html(surface.id)} · #{escape_html(state)}", <<~HTML)
          <div class="stage">
            <img src="#{data_uri(image_path)}" alt="blurred composition for squint review">
          </div>
        HTML
      end

      def grid(surface:, state:, image_path:, step:)
        css = "#{BASE_IMAGE_CSS}.grid{position:absolute;inset:0;pointer-events:none;" \
              "background-image:linear-gradient(to right,rgba(17,17,17,.12) 1px,transparent 1px)," \
              "linear-gradient(to bottom,rgba(17,17,17,.12) 1px,transparent 1px);background-size:#{step}px #{step}px}" \
              ".vcenter,.hcenter{position:absolute;background:rgba(220,99,92,.8);pointer-events:none}" \
              ".vcenter{top:0;bottom:0;width:1px;left:50%}.hcenter{left:0;right:0;height:1px;top:50%}"
        document(css, "registration grid · #{escape_html(surface.id)} · #{escape_html(state)} · #{step}px", <<~HTML)
          <div class="stage">
            <img src="#{data_uri(image_path)}" alt="current render">
            <div class="grid"></div><div class="vcenter"></div><div class="hcenter"></div>
          </div>
        HTML
      end

      def document(css, header, body)
        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>#{BASE_CSS}#{css}</style></head><body>
          <header>#{header}</header>
          #{body}
          </body></html>
        HTML
      end

      def data_uri(path) = "data:image/png;base64,#{Base64.strict_encode64(File.binread(path))}"

      def escape_html(value)
        value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
      end
    end
  end
end
