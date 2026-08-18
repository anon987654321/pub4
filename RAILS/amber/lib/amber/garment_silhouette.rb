# frozen_string_literal: true

require "vips"

module Amber
  # Flat garment cut-outs for the demo wardrobe, drawn rather than downloaded.
  #
  # The seeder used to attach picsum photographs keyed by the garment's name, so
  # the mannequin on the landing page wore a doorway, a street scene and a beach:
  # the zone overlays are object-fit boxes over the figure, and a photograph fills
  # them edge to edge. A cut-out with an alpha channel is the shape that surface
  # was built for — the figure shows through around the garment.
  #
  # Drawn as SVG and rasterised through vips, so there is no image to license, no
  # network at seed time, and the colour comes from the item's own `color`.
  module GarmentSilhouette
    # Named colours the demo wardrobe uses, as the garment would look on a rail.
    # Anything unknown falls back to a neutral, never to nothing.
    COLORS = {
      "ivory" => "#f2ece0", "camel" => "#b8875a", "black" => "#2a2724",
      "oatmeal" => "#ded3c0", "charcoal" => "#4a4844", "navy" => "#2b3a55",
      "sage" => "#a8b49a", "tan" => "#c39a6b", "blush" => "#e8c4bd",
      "indigo" => "#3b4a6b", "gold" => "#c9a227", "rust" => "#a85c3c",
      "tortoise" => "#7a5230", "white" => "#f7f5f2", "navy/white" => "#2b3a55"
    }.freeze
    NEUTRAL = "#b9b2a6"

    # Shape per garment, chosen by what the title says it is. Category alone is
    # too coarse — "Bottoms" is trousers, jeans, a skirt and shorts, and they do
    # not share an outline.
    SHAPE_BY_KEYWORD = {
      "slip dress" => :dress, "shirtdress" => :shirtdress, "dress" => :dress,
      "wrap coat" => :coat, "coat" => :coat, "blazer" => :blazer,
      "cashmere" => :sweater, "crew neck" => :sweater, "blouse" => :blouse,
      "tee" => :tee, "trousers" => :trousers, "jeans" => :jeans,
      "shorts" => :shorts, "skirt" => :skirt, "boots" => :boots,
      "trainers" => :trainers, "crossbody" => :bag, "earrings" => :earrings,
      "beanie" => :beanie, "sunglasses" => :sunglasses
    }.freeze

    SHAPE_BY_CATEGORY = {
      "Dresses" => :dress, "Outerwear" => :coat, "Tops" => :sweater,
      "Bottoms" => :trousers, "Shoes" => :boots, "Accessories" => :bag
    }.freeze

    module_function

    def shape_for(title:, category: nil)
      key = title.to_s.downcase
      SHAPE_BY_KEYWORD.each { |word, shape| return shape if key.include?(word) }
      SHAPE_BY_CATEGORY.fetch(category.to_s, :sweater)
    end

    def hex_for(color)
      COLORS.fetch(color.to_s.downcase, NEUTRAL)
    end

    # PNG bytes with an alpha channel, or nil if this box has no vips that can
    # read SVG — the caller then keeps whatever it did before rather than
    # attaching nothing.
    def png(title:, color:, category: nil, width: 720)
      svg = svg_for(shape_for(title: title, category: category), hex_for(color))
      image = Vips::Image.new_from_buffer(svg, "")
      image = image.resize(width.to_f / image.width) if image.width != width
      image.write_to_buffer(".png")
    rescue Vips::Error, LoadError => error
      warn_once(error)
      nil
    end

    def svg_for(shape, fill)
      body = PATHS.fetch(shape) { PATHS.fetch(:sweater) }.call(fill)
      %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 520" width="400" height="520">#{body}</svg>)
    end

    def warn_once(error)
      return if @warned

      @warned = true
      Rails.logger.warn("GarmentSilhouette: vips cannot rasterise SVG (#{error.class}) — demo photos left as they were") if defined?(Rails)
    end

    # One entry per outline. Flat fills and a single seam line, matching the flat
    # rule the rest of the family is held to — no gradients, no shadow. The seam
    # is a shade of the garment's own colour: drawn at the same hue it was
    # invisible, which left a coat and a tee the same silhouette.
    def self.shade(hex, factor = 0.72)
      rgb = hex.delete_prefix("#").scan(/../).map { |pair| (pair.to_i(16) * factor).round.clamp(0, 255) }
      format("#%02x%02x%02x", *rgb)
    end

    def self.seam(color) = %(stroke="#{shade(color)}" stroke-width="5" fill="none" stroke-linecap="round")

    PATHS = {
      sweater: ->(fill) {
        %(<path d="M120 110 L170 80 L230 80 L280 110 L330 150 L305 195 L280 175 L280 440 L120 440 L120 175 L95 195 L70 150 Z" fill="#{fill}"/>) +
          %(<path d="M170 80 Q200 108 230 80" #{seam(fill)}/>)
      },
      blouse: ->(fill) {
        %(<path d="M125 115 L175 82 L200 105 L225 82 L275 115 L322 155 L300 198 L278 180 L278 430 L122 430 L122 180 L100 198 L78 155 Z" fill="#{fill}"/>) +
          %(<path d="M200 105 L200 425" #{seam(fill)}/>)
      },
      tee: ->(fill) {
        %(<path d="M130 110 L175 85 L225 85 L270 110 L330 145 L300 190 L272 172 L272 380 L128 380 L128 172 L100 190 L70 145 Z" fill="#{fill}"/>) +
          %(<path d="M175 85 Q200 112 225 85" #{seam(fill)}/>)
      },
      coat: ->(fill) {
        %(<path d="M112 100 L172 70 L228 70 L288 100 L348 160 L312 214 L288 190 L288 486 L112 486 L112 190 L88 214 L52 160 Z" fill="#{fill}"/>) +
          %(<path d="M200 128 L200 480" #{seam(fill)}/>) +
          %(<path d="M172 70 L200 128 L228 70" #{seam(fill)}/>) +
          %(<path d="M112 300 L288 300" #{seam(fill)}/>)
      },
      blazer: ->(fill) {
        %(<path d="M116 104 L174 74 L226 74 L284 104 L340 156 L310 206 L284 186 L284 402 L116 402 L116 186 L90 206 L60 156 Z" fill="#{fill}"/>) +
          %(<path d="M174 74 L200 176 L226 74" #{seam(fill)}/>) +
          %(<path d="M200 176 L200 402" #{seam(fill)}/>)
      },
      dress: ->(fill) {
        %(<path d="M150 90 L200 70 L250 90 L262 200 L300 470 L100 470 L138 200 Z" fill="#{fill}"/>) +
          %(<path d="M150 90 Q200 120 250 90" #{seam(fill)}/>)
      },
      shirtdress: ->(fill) {
        %(<path d="M140 95 L178 72 L200 96 L222 72 L260 95 L276 205 L305 470 L95 470 L124 205 Z" fill="#{fill}"/>) +
          %(<path d="M200 96 L200 465" #{seam(fill)}/>)
      },
      skirt: ->(fill) {
        %(<path d="M140 150 L260 150 L310 430 L90 430 Z" fill="#{fill}"/>) +
          %(<path d="M140 172 L260 172" #{seam(fill)}/>)
      },
      trousers: ->(fill) {
        %(<path d="M138 120 L262 120 L272 250 L268 470 L212 470 L200 285 L188 470 L132 470 L128 250 Z" fill="#{fill}"/>) +
          %(<path d="M138 148 L262 148" #{seam(fill)}/>)
      },
      jeans: ->(fill) {
        %(<path d="M144 120 L256 120 L266 250 L258 470 L214 470 L200 290 L186 470 L142 470 L134 250 Z" fill="#{fill}"/>) +
          %(<path d="M144 150 L256 150" #{seam(fill)}/>) +
          %(<path d="M200 160 L200 285" #{seam(fill)}/>)
      },
      shorts: ->(fill) {
        %(<path d="M140 150 L260 150 L268 240 L262 340 L212 340 L200 260 L188 340 L138 340 L132 240 Z" fill="#{fill}"/>) +
          %(<path d="M140 178 L260 178" #{seam(fill)}/>)
      },
      boots: ->(fill) {
        %(<path d="M120 176 L178 176 L178 322 Q178 340 196 342 L206 344 L206 386 L106 386 L106 344 Q120 340 120 322 Z" fill="#{fill}"/>) +
          %(<path d="M222 176 L280 176 L280 322 Q280 340 298 342 L308 344 L308 386 L208 386 L208 344 Q222 340 222 322 Z" fill="#{fill}"/>) +
          %(<path d="M106 372 L206 372" #{seam(fill)}/>) +
          %(<path d="M208 372 L308 372" #{seam(fill)}/>)
      },
      trainers: ->(fill) {
        %(<path d="M104 286 Q136 236 180 252 L194 296 L204 344 L100 344 Q92 310 104 286 Z" fill="#{fill}"/>) +
          %(<path d="M216 286 Q248 236 292 252 L306 296 L316 344 L212 344 Q204 310 216 286 Z" fill="#{fill}"/>) +
          %(<path d="M100 330 L204 330" #{seam(fill)}/>) +
          %(<path d="M212 330 L316 330" #{seam(fill)}/>)
      },
      bag: ->(fill) {
        %(<path d="M140 220 L260 220 L276 380 L124 380 Z" fill="#{fill}"/>) +
          %(<path d="M160 220 Q200 120 240 220" #{seam(fill)}/>)
      },
      beanie: ->(fill) {
        %(<path d="M120 260 Q120 150 200 150 Q280 150 280 260 Z" fill="#{fill}"/>) +
          %(<rect x="112" y="258" width="176" height="34" rx="14" fill="#{fill}"/>)
      },
      sunglasses: ->(fill) {
        %(<rect x="96" y="230" width="94" height="62" rx="18" fill="#{fill}"/>) +
          %(<rect x="210" y="230" width="94" height="62" rx="18" fill="#{fill}"/>) +
          %(<path d="M190 252 L210 252" #{seam(fill)}/>)
      },
      earrings: ->(fill) {
        %(<circle cx="128" cy="270" r="44" fill="none" stroke="#{fill}" stroke-width="16"/>) +
          %(<circle cx="272" cy="270" r="44" fill="none" stroke="#{fill}" stroke-width="16"/>)
      }
    }.freeze
  end
end
