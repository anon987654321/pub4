# frozen_string_literal: true

require_relative "../operator/master_design"

module Shared
  # One composition system for storefront campaign art.
  #
  # The image prompt describes only the product scene. Copy is returned
  # separately so Rails can render exact prices, headlines and CTAs.
  class PromotionalArt
    Result = Data.define(
      :layout, :background, :background_color, :background_ink, :product, :headline, :body, :price, :badge, :cta,
      :image_prompt, :negative_prompt, :safe_inset, :copy_zone, :product_zone
    )

    def self.build(product:, headline:, body: nil, price: nil, badge: nil, cta: nil,
                   layout: :hero, background: :chalk)
      new(
        product:, headline:, body:, price:, badge:, cta:,
        layout:, background:
      ).build
    end

    def initialize(product:, headline:, body: nil, price: nil, badge: nil, cta: nil,
                   layout: :hero, background: :chalk)
      @system = Operator::MasterDesign.design_system.fetch("promotional_art")
      @product = product.to_s.strip
      @headline = headline.to_s.strip
      @body = body.to_s.strip.presence
      @price = price.to_s.strip.presence
      @badge = badge.to_s.strip.presence
      @cta = cta.to_s.strip.presence
      @layout = layout.to_s
      @background = background.to_s
      validate!
    end

    def build
      config = @system.fetch("layouts").fetch(@layout)
      matte = @system.fetch("matte_backgrounds").fetch(@background)
      Result.new(
        @layout,
        @background,
        matte,
        @system.fetch("matte_inks").fetch(@background),
        @product,
        @headline,
        @body,
        @price,
        @badge,
        @cta,
        image_prompt(config, matte),
        Array(@system.dig("generation", "prompt_negative")),
        config.fetch("safe_inset"),
        config.fetch("copy_zone"),
        config.fetch("product_zone")
      )
    end

    private

    def validate!
      raise ArgumentError, "promotional product is required" if @product.blank?
      raise ArgumentError, "promotional headline is required" if @headline.blank?
      raise ArgumentError, "unknown promotional layout: #{@layout}" unless @system.fetch("layouts").key?(@layout)
      raise ArgumentError, "unknown promotional background: #{@background}" unless @system.fetch("matte_backgrounds").key?(@background)

      copy = @system.fetch("copy")
      raise ArgumentError, "promotional headline is too long" if @headline.length > copy.fetch("max_headline_characters")
      raise ArgumentError, "promotional body is too long" if @body && @body.length > copy.fetch("max_body_characters")
      raise ArgumentError, "promotional badge is too long" if @badge && @badge.split.size > copy.fetch("max_badge_words")
      raise ArgumentError, "promotional CTA is too long" if @cta && @cta.split.size > copy.fetch("max_cta_words")
    end

    def image_prompt(layout, matte)
      [
        "clean ecommerce campaign still life",
        "product: #{@product}",
        "single primary product, fully visible, centered in its product zone",
        "product scale #{layout.fetch("product_zone")}",
        "matte background #{matte} with nearly uniform tone",
        "safe copy area #{layout.fetch("copy_zone")} kept visually quiet",
        "large soft studio source, neutral white balance",
        "soft natural contact shadow only",
        "crisp product silhouette",
        "realistic material texture",
        "#{layout.fetch("aspect_ratio")} composition",
        "editorial product photography",
        "no typography or marketing copy rendered in the image"
      ].join(", ")
    end
  end
end
