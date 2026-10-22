# frozen_string_literal: true

require "json"
require_relative "cdp_session"

module Deploy
  # The face Chrome painted, not the face the stylesheet asked for. A computed
  # font-family is a wish list; a missing web font silently falls through it,
  # so a rule that reads only the first family certifies a stack the page does
  # not wear. CSS.getPlatformFontsForNode answers per element with the
  # platform font names and how many glyphs each painted.
  module PaintedFonts
    SELECT = File.read(File.join(__dir__, "geometry_probe/painted_fonts_select.js")).freeze
    LIMIT = 60

    module_function

    # {"painted_fonts" => {key => [{"name", "glyphs"}]}, "painted_fonts_status" => "ok"}
    # or an "unverified: reason" status with no fonts, so a consumer falls back
    # to the computed stack and says so.
    def probe(cdp, limit: LIMIT)
      keys = Array(cdp.evaluate(SELECT.sub("__LIMIT__", limit.to_s)))
      return status("unverified: no text elements sampled") if keys.empty?

      cdp.command("DOM.enable")
      cdp.command("CSS.enable")
      fonts = collect(cdp, keys)
      fonts.empty? ? status("unverified: CDP returned no platform fonts") : { "painted_fonts" => fonts, "painted_fonts_status" => "ok" }
    rescue CdpSession::Error, NoMethodError => e
      status("unverified: #{e.class.name.split("::").last} #{e.message[0, 80]}")
    ensure
      untag(cdp)
    end

    def collect(cdp, keys)
      root = cdp.command("DOM.getDocument", depth: 0).dig("root", "nodeId")
      ids = cdp.command("DOM.querySelectorAll", nodeId: root, selector: "[data-gp-font]")["nodeIds"]
      Array(ids).each_with_object({}) do |node_id, out|
        index = cdp.command("DOM.getAttributes", nodeId: node_id)["attributes"].each_slice(2).to_h["data-gp-font"].to_i
        rows = cdp.command("CSS.getPlatformFontsForNode", nodeId: node_id)["fonts"]
        out[keys[index]] = rank(rows) if keys[index]
      end
    end

    # Most glyphs first: the dominant face is the one the reader sees.
    def rank(rows)
      Array(rows).map { |f| { "name" => f["familyName"].to_s, "glyphs" => f["glyphCount"].to_i } }
                 .sort_by { |f| -f["glyphs"] }
    end

    def status(note) = { "painted_fonts_status" => note }

    def untag(cdp)
      cdp.evaluate("document.querySelectorAll('[data-gp-font]').forEach(e => e.removeAttribute('data-gp-font'))")
    rescue CdpSession::Error
      nil
    end
  end
end
