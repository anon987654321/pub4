# frozen_string_literal: true

require "test_helper"

# The demo wardrobe's photographs came from picsum keyed by the garment's name,
# so the landing page's mannequin wore a doorway, a street scene and a beach.
# These pin the cut-outs that replaced them.
class GarmentSilhouetteTest < ActiveSupport::TestCase
  test "the shape comes from what the title says the garment is" do
    assert_equal :coat, Amber::GarmentSilhouette.shape_for(title: "Camel wool wrap coat", category: "Outerwear")
    assert_equal :blazer, Amber::GarmentSilhouette.shape_for(title: "Navy oversized blazer", category: "Outerwear")
    assert_equal :boots, Amber::GarmentSilhouette.shape_for(title: "Black pointed-toe ankle boots", category: "Shoes")
    assert_equal :trainers, Amber::GarmentSilhouette.shape_for(title: "White leather trainers", category: "Shoes")
  end

  # Category alone cannot tell trousers from a skirt, and "Bottoms" holds both.
  test "category is the fallback, not the answer" do
    assert_equal :skirt, Amber::GarmentSilhouette.shape_for(title: "Sage pleated midi skirt", category: "Bottoms")
    assert_equal :jeans, Amber::GarmentSilhouette.shape_for(title: "Indigo straight-leg jeans", category: "Bottoms")
    assert_equal :trousers, Amber::GarmentSilhouette.shape_for(title: "Something unnameable", category: "Bottoms")
  end

  test "an unknown colour draws in the neutral rather than not at all" do
    assert_equal Amber::GarmentSilhouette::NEUTRAL, Amber::GarmentSilhouette.hex_for("chartreuse-mist")
    assert_equal "#2b3a55", Amber::GarmentSilhouette.hex_for("Navy")
  end

  # The point of the cut-out: the figure shows through around the garment.
  test "the png carries an alpha channel" do
    png = Amber::GarmentSilhouette.png(title: "Camel wool wrap coat", color: "camel", width: 200)
    skip "vips on this box cannot rasterise SVG" if png.nil?

    image = Vips::Image.new_from_buffer(png, "")
    assert_equal 4, image.bands
    assert_equal 200, image.width
    assert_equal 0, image.extract_band(3).extract_area(0, 0, 4, 4).max, "the corner should be transparent"
  end

  test "the seam is a darker shade of the garment, not the same hue" do
    assert_equal "#846141", Amber::GarmentSilhouette.shade("#b8875a")
  end
# The overlay renders object-fit: contain inside a zone box, so transparent
# margin around the shape is margin the garment loses on the figure.
test "the cut-out is trimmed to the garment" do
  png = Amber::GarmentSilhouette.png(title: "Gold hoop earrings", color: "gold", width: 300)
  skip "vips on this box cannot rasterise SVG" if png.nil?

  image = Vips::Image.new_from_buffer(png, "")
  assert_equal 300, image.width
  assert_operator image.height, :<, 200, "a pair of hoops should not carry a garment-length canvas"
  assert_operator image.extract_band(3).max, :>, 200, "something should be drawn"
end
end
