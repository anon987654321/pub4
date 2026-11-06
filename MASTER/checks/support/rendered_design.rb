# frozen_string_literal: true

require "json"
require "yaml"

module Deploy
  # The design-book Laws' rendered half (MASTER/law/rendered.rb and the render adapters beside
  # their source detectors), as pure Ruby over one snapshot that
  # geometry_probe/design_laws.js measured: computed styles, line boxes, chrome states,
  # focus stops, text spacing, motion and transfer bytes, at 390, 360 and 320 before desktop.
  #
  # One evaluator per Law, registered by id. The Law's bad and good fixtures are snapshots,
  # so it proves at load like any other Law; the rendered suite (DesignLawsCheck) and the
  # headless fixture test feed it snapshots the browser measured. Each evaluator answers
  # messages; a missing measurement answers none, and the caller reports that INCONCLUSIVE.
  module RenderedDesign
    MOBILE = [390, 360, 320].freeze
    ROOT = File.expand_path("../..", __dir__)
    EVALUATORS = {} # scan: intentional - the registry each evaluator file fills as it loads
    SNAPSHOT = /\.rendered\.json\z/
    EXAMPLE = "/repo/MASTER/var/rendered/home.rendered.json"
    WEIGHTS = [0.2126, 0.7152, 0.0722].freeze
    WHITE = [255, 255, 255, 1].freeze

    def self.register(id, &block) = EVALUATORS[id.to_s] = block

    def self.ids = EVALUATORS.keys

    # Messages for one Law over a snapshot (a Hash, or its JSON text).
    def self.judge(id, snapshot)
      snap = snapshot.is_a?(String) ? JSON.parse(snapshot) : snapshot
      return [] unless snap.is_a?(Hash) && snap["probe"] == "design_laws"

      Array(EVALUATORS.fetch(id.to_s).call(snap)).select { |row| row.is_a?(String) }.uniq
    rescue JSON::ParserError # scan: intentional - a file that is not a snapshot holds no rendered finding
      []
    end

    # The Law check body: one finding per message, on line 1 of the snapshot.
    def self.findings(id, text, path)
      return [] unless path.to_s.end_with?(".rendered.json")

      judge(id, text).map { |message| { line: 1, message: } }
    end

    def self.views(snap, widths = MOBILE)
      rows = Array(snap["viewports"])
      widths ? rows.select { |view| widths.include?(view["width"].to_i) } : rows
    end

    def self.elements(view) = Array(view["elements"])

    def self.each_view(snap, widths = MOBILE, &) = views(snap, widths).flat_map(&)

    def self.each_text(snap, &) = each_view(snap) { |view| texts(view).filter_map(&) }

    def self.texts(view)
      elements(view).reject { |el| el["text"].to_s.strip.empty? || el["mono"] || el["canvas"] }
    end

    # sRGB relative luminance and WCAG contrast, over [r, g, b, a] composited on its ground.
    def self.luminance(rgb)
      linear = rgb.first(3).map do |value|
        channel = value.to_f / 255
        channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
      end
      linear.zip(WEIGHTS).sum { |channel, weight| channel * weight }
    end

    def self.blend(top, under)
      alpha = top.fetch(3, 1).to_f
      top.first(3).zip(under.first(3)).map { |one, two| (one.to_f * alpha) + (two.to_f * (1 - alpha)) } + [1]
    end

    def self.contrast(ink, ground)
      base = ground || WHITE
      high, low = [luminance(blend(ink, base)), luminance(base)].minmax.reverse
      ((high + 0.05) / (low + 0.05)).round(2)
    end

    # [saturation, lightness] in 0..1.
    def self.hsl(rgb)
      channels = rgb.first(3).map { |value| value.to_f / 255 }
      high, low = channels.minmax.reverse
      light = (high + low) / 2
      return [0.0, light] if high == low

      delta = high - low
      [light > 0.5 ? delta / (2 - high - low) : delta / (high + low), light]
    end

    def self.center(rect) = [rect["x"].to_f + (rect["w"].to_f / 2), rect["y"].to_f + (rect["h"].to_f / 2)]

    def self.tokens
      @tokens ||= YAML.safe_load_file(File.join(ROOT, "data/tokens.yml"), aliases: true)
    rescue Errno::ENOENT # scan: intentional - without tokens.yml no size is a token, and the finding says so
      {}
    end

    # A snapshot for a Law's fixture: one 390 viewport with the elements given.
    def self.fixture(elements: [], **view)
      row = { "width" => 390, "height" => 844, "elements" => elements }.merge(view.transform_keys(&:to_s))
      { "probe" => "design_laws", "viewports" => [row] }.to_json
    end

    ELEMENT = {
      "text" => "Tekst", "rect" => { "x" => 16, "y" => 16, "w" => 358, "h" => 24 }, "font_size" => 16,
      "font_weight" => 400, "line_height" => 24, "letter_spacing" => 0, "lines" => 1, "color" => [17, 17, 17, 1],
      "bg" => [0, 0, 0, 0], "ground" => WHITE, "own_ground" => WHITE, "attrs" => {}, "decoration" => "none"
    }.freeze

    def self.element(key, **fields)
      ELEMENT.merge("key" => key, "tag" => key[/\A[a-z0-9]+/]).merge(fields.transform_keys(&:to_s))
    end
  end
end

require_relative "rendered_design/type_laws"
require_relative "rendered_design/layout_laws"
require_relative "rendered_design/access_laws"
