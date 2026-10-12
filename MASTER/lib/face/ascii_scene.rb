# frozen_string_literal: true

require "digest"
require "json"
require_relative "../face"
require_relative "../cli/face/depth_map"
require_relative "../cli/face/glyphs"
require_relative "../cli/face/features"
require_relative "../cli/face/head"
require_relative "../cli/face/mesh"
require_relative "../cli/face/ascii"

module Master
  module Face
    # Bounded scene payload built from the canonical terminal Head points.
    # The web face samples these points rather than declaring another anatomy.
    module AsciiScene
      ROWS = 28
      COLS = 64
      MAX_POINTS = 1_100
      module_function

      def browser_payload(root: Master::ROOT, rows: ROWS, cols: COLS, max_points: MAX_POINTS)
        source = Master::CLI::Face::Head.for(rows, cols)
        points = []
        source.each_point do |x, y, z, brightness, zone, _phase|
          points << [x.round(5), y.round(5), z.round(5), brightness.round(5), zone.to_i]
        end
        limit = [Integer(max_points), 1].max
        stride = [(points.size.to_f / limit).ceil, 1].max
        points = points.each_with_index.filter_map { |point, index| point if (index % stride).zero? }
        laws = LawField.laws(root:)
        {
          schema: 1,
          available: true,
          rows:,
          cols:,
          points:,
          point_digest: Digest::SHA256.hexdigest(JSON.generate(points)),
          laws:,
          law_digest: LawField.browser_payload(root:).fetch(:digest),
          toggle_key: LawField.config(root:).fetch("web_toggle_key", "v")
        }
      rescue StandardError => e
        { schema: 1, available: false, points: [], laws: [], error: "#{e.class}: #{e.message}" }
      end
    end
  end
end
