# frozen_string_literal: true

require_relative "visual_ghost_pages"

module Master
  module Fix
    # The HTML pages the cross-page overlay screenshots. Every layer is placed at
    # the top-left of one stage at its own pixel scale, so the same chrome on
    # two pages lands on the same pixels and any difference shows as a smear.
    module VisualCrossPagePages
      PALETTE = %w[#06b6d4 #a855f7 #f59e0b #22c55e #ef4444 #3b82f6 #ec4899 #84cc16].freeze
      STAGE_CSS = ".stage{position:relative;overflow:hidden;background:#fff;border:1px solid #bbb;line-height:0}" \
                  ".stage img{position:absolute;left:0;top:0;width:auto;height:auto;max-width:none}" \
                  ".stage svg{position:absolute;left:0;top:0;pointer-events:none}" \
                  ".legend{margin:0 0 12px;font-size:13px;line-height:1.5}.legend b{display:inline-block;padding:0 6px;color:#fff}"

      module_function

      # layers: [{ id:, path:, opacity:, boxes: [{ name:, rect: }] }] in draw order.
      # width/height clip the stage; note says how the layers were aligned.
      def overlay(title:, note:, layers:, width:, height:)
        images = layers.map { |l| %(<img src="#{VisualGhostPages.data_uri(l[:path])}" alt="#{esc(l[:id])}" style="opacity:#{l[:opacity]};">) }
        outlines = layers.each_with_index.flat_map { |l, i| l[:boxes].map { |b| outline(b, PALETTE[i % PALETTE.size]) } }
        legend = layers.each_with_index.map { |l, i| %(<b style="background:#{PALETTE[i % PALETTE.size]}">#{esc(l[:id])}</b>) }.join(" ")
        VisualGhostPages.document(STAGE_CSS, esc(title), <<~HTML)
          <p class="legend">#{esc(note)}<br>outline colour = page: #{legend}</p>
          <div class="stage" style="width:#{width}px;height:#{height}px">
            #{images.join}
            <svg width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" aria-hidden="true">#{outlines.join}</svg>
          </div>
        HTML
      end

      def outline(box, color)
        r = box[:rect]
        %(<rect x="#{r["x"]}" y="#{r["y"]}" width="#{r["w"]}" height="#{r["h"]}" fill="none" stroke="#{color}" stroke-width="1.5"/>) +
          %(<text x="#{r["x"] + 2}" y="#{r["y"] + 11}" fill="#{color}" font-size="10">#{esc(box[:name])}</text>)
      end

      def esc(value) = VisualGhostPages.escape_html(value)
    end
  end
end
