# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/brgen_commerce"
require_relative "../../app/services/commerce_fit"

class CommerceFitTest < ActiveSupport::TestCase
  Product = Data.define(
    :id, :title, :description, :merchant, :category, :price_cents, :currency,
    :condition, :availability, :delivery, :trust, :url, :image_url, :reasons, :metadata
  )

  test "category and wardrobe language produce explainable fit" do
    item = Item.new(title: "Wool coat", category: "Outerwear", brand: "Aster", color: "navy", material: "wool")
    product = Product.new(
      "pub4-commerce-v1:brgen:listing:1:2",
      "Aster wool coat",
      "Navy wool outerwear",
      "Local shop",
      "Outerwear",
      12_000,
      "NOK",
      "very_good",
      { "buyable" => true },
      { "label" => "Next day" },
      { "seller_score" => 0.9 },
      "https://example.test/listing",
      nil,
      [],
      { "source" => "brgen" }
    )

    result = CommerceFit.evaluate(item, product)

    assert_operator result.score, :>, 0.5
    assert_includes result.reasons.join(" "), "category"
  end

  test "same category with strong title overlap exposes duplicate risk" do
    item = Item.new(title: "Black cotton shirt", category: "Tops", color: "black", material: "cotton")
    product = Product.new(
      "pub4-commerce-v1:brgen:listing:1:3",
      "Black cotton shirt",
      "",
      "Local shop",
      "Tops",
      2_000,
      "NOK",
      "good",
      {},
      {},
      {},
      "https://example.test/listing",
      nil,
      [],
      { "source" => "brgen" }
    )

    result = CommerceFit.evaluate(item, product)

    assert result.duplicate_risk
    assert result.reasons.any? { |reason| reason.include?("duplicate") }
  end
end
