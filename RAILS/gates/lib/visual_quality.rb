# frozen_string_literal: true

require "yaml"

module Deploy
  # Page-level visual *quality* (not pixel regression).
  # Scores landmarks, hierarchy, CTA budget (Hick), guest-open, dialect purity, density.
  class VisualQuality
    DATA = File.join(File.expand_path("..", __dir__), "data", "exemplars.yml")

    Result = Struct.new(:surface, :score, :max, :target, :notes, keyword_init: true) do
      def pass?
        score >= target
      end
    end

    def self.load(path = DATA)
      YAML.safe_load_file(path).fetch("quality")
    end

    def initialize(config: nil)
      @config = config || self.class.load
      @weights = @config.fetch("weights")
      @rules = @config.fetch("rules")
      @target = @config["target_score"].to_i
    end

    # surface: :marketplace | :live | :dating | :social | :generic
    def score(html, surface: :generic)
      body = normalize(html)
      max = @weights.values.sum
      earned = 0
      notes = []

      earned += score_landmarks(body, notes)
      earned += score_hierarchy(body, notes)
      earned += score_cta_budget(body, notes)
      earned += score_guest_open(body, notes)
      earned += score_dialect(body, surface, notes)
      earned += score_density(body, notes)

      Result.new(surface: surface.to_s, score: earned, max: max, target: @target, notes: notes)
    end

    # Optional PNG content-signal ratio (soft). Requires chunky_png.
    # Counts pixels that are neither crushed black nor blown white — works for
    # dark and light UIs (text/chrome sit in the midtones).
    def png_ink_ratio(path)
      require "chunky_png"
      img = ChunkyPNG::Image.from_file(path)
      total = img.width * img.height
      return nil if total.zero?

      step = [1, (total / 50_000.0).ceil].max
      signal = 0
      count = 0
      i = 0
      img.pixels.each do |px|
        if (i % step).zero?
          r = ChunkyPNG::Color.r(px)
          g = ChunkyPNG::Color.g(px)
          b = ChunkyPNG::Color.b(px)
          lum = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
          # midtone / chromatic content (not pure black canvas or pure white void)
          signal += 1 if lum > 18 && lum < 240
          count += 1
        end
        i += 1
      end
      return nil if count.zero?

      (signal.to_f / count).round(4)
    rescue LoadError, StandardError
      nil
    end

    private

    def normalize(html)
      body = html.to_s.dup.force_encoding(Encoding::UTF_8)
      body = body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless body.valid_encoding?
      body
    end

    def w(key)
      @weights[key.to_s].to_i
    end

    def score_landmarks(body, notes)
      pts = w(:landmarks)
      rules = @rules["landmarks"] || {}
      ok = Array(rules["require_any"]).any? { |p| body.match?(Regexp.new(p, Regexp::IGNORECASE)) }
      unless ok
        notes << "landmarks:missing"
        return 0
      end
      pts
    end

    def score_hierarchy(body, notes)
      pts = w(:hierarchy)
      h1 = body.scan(/<h1\b/i).size
      max_h1 = @rules.dig("hierarchy", "max_h1").to_i
      max_h1 = 1 if max_h1 <= 0
      if h1 > max_h1
        notes << "hierarchy:h1=#{h1}"
        return 0
      end
      if h1.zero?
        notes << "hierarchy:no_h1"
        return (pts * 0.5).floor
      end
      pts
    end

    def score_cta_budget(body, notes)
      pts = w(:cta_budget)
      submits = body.scan(/type=["']submit["']|<button\b/i).size
      primary = body.scan(/btn-primary|button_to/i).size
      max_sub = @rules.dig("cta_budget", "max_submit_buttons").to_i
      max_pri = @rules.dig("cta_budget", "max_btn_primary").to_i
      max_sub = 4 if max_sub <= 0
      max_pri = 3 if max_pri <= 0
      score = pts
      if submits > max_sub
        notes << "cta:submits=#{submits}"
        score = (score * 0.4).floor
      end
      if primary > max_pri
        notes << "cta:primary=#{primary}"
        score = (score * 0.5).floor
      end
      score
    end

    def score_guest_open(body, notes)
      pts = w(:guest_open)
      forbid = @rules.dig("guest_open", "forbid")
      if forbid && body.match?(Regexp.new(forbid, Regexp::IGNORECASE))
        notes << "guest_open:auth_wall"
        return 0
      end
      pts
    end

    def score_dialect(body, surface, notes)
      pts = w(:dialect_purity)
      key =
        case surface.to_s
        when "marketplace" then "marketplace_forbids"
        when "live" then "live_forbids"
        when "dating" then "dating_forbids"
        else nil
        end
      return pts unless key

      forbid = @rules.dig("dialect_purity", key)
      if forbid && body.match?(Regexp.new(forbid, Regexp::IGNORECASE))
        notes << "dialect:#{surface}"
        return 0
      end
      pts
    end

    def score_density(body, notes)
      pts = w(:density)
      min_bytes = @rules.dig("density", "min_bytes").to_i
      min_bytes = 400 if min_bytes <= 0
      if body.bytesize < min_bytes
        notes << "density:thin=#{body.bytesize}"
        return 0
      end
      pts
    end
  end
end
