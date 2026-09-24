# frozen_string_literal: true

require "base64"

module Master
  module Fix
    # Every captured surface and mobile journey state on one page, screenshotted
    # to one image, so Council judges the surfaces against each other rather
    # than one at a time.
    class VisualContactSheet
      def initialize(dir:, root:)
        @dir = dir
        @root = root
      end

      def render(captures)
        html_path = File.join(@dir, "rendered-ui-contact-sheet.html")
        File.write(html_path, page(captures))
        screenshot = File.join(@dir, "rendered-ui-contact-sheet.png")
        Deploy::GeometryProbe.with_browser(root: @root, warm: []) do |cdp|
          cdp.viewport(1800, 1400, mobile: false)
          cdp.navigate("file://#{html_path}")
          cdp.screenshot(screenshot, capture_beyond_viewport: true)
        end
        screenshot
      end

      private

      def page(captures)
        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>
          * { box-sizing: border-box; }
          html, body { margin: 0; background: #fff; color: #111; }
          body { padding: 24px; font: 16px/1.4 system-ui, sans-serif; }
          h1 { margin: 0 0 20px; font-size: 24px; }
          .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 24px; }
          figure { margin: 0; min-width: 0; } figcaption { margin: 0 0 8px; font-weight: 700; }
          img { display: block; width: 100%; height: auto; border: 1px solid #bbb; }
          </style></head><body>
          <h1>MASTER rendered visual evidence: #{captures.length} surfaces</h1>
          <div class="grid">#{captures.flat_map { |capture| items(capture) }.join("\n")}</div>
          </body></html>
        HTML
      end

      def items(capture)
        # The back/forward return-path states carry no screenshot; they reach
        # Council as text in the context rows, not as a figure here.
        [item(capture)] + Array(capture[:journeys]).filter_map do |journey|
          next unless journey["screenshot"]
          journey_item(capture[:surface], journey)
        end
      end

      def journey_item(surface, journey)
        encoded = Base64.strict_encode64(File.binread(journey.fetch("screenshot")))
        label = "#{surface.id} | mobile state=#{journey["kind"]} | #{journey["label"]}"
        %(<figure><figcaption>#{escape_html(label)}</figcaption><img src="data:image/png;base64,#{encoded}" alt="#{escape_html(label)}"></figure>)
      rescue StandardError => e
        "<figure><figcaption>#{escape_html(surface.id)} | journey evidence error: #{escape_html(e.message)}</figcaption></figure>"
      end

      def item(capture)
        surface = capture[:surface]
        encoded = Base64.strict_encode64(File.binread(capture[:screenshot]))
        label = "#{surface.id} | #{surface.viewport} | #{surface.url}"
        "<figure><figcaption>#{escape_html(label)}</figcaption><img src=\"data:image/png;base64,#{encoded}\" alt=\"#{escape_html(label)}\"></figure>"
      rescue StandardError => e
        "<figure><figcaption>#{escape_html(surface.id)} | contact-sheet error: #{escape_html(e.message)}</figcaption></figure>"
      end

      def escape_html(value)
        value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
      end
    end
  end
end
