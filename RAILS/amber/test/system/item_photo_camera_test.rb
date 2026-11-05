# frozen_string_literal: true

require "application_system_test_case"
require "zlib"

# The item form keeps its gallery picker and adds a camera input a phone opens
# straight to the rear camera. A photo taken there joins the picked photos in
# the gallery input, the one input that uploads.
class ItemPhotoCameraTest < ApplicationSystemTestCase
  test "a photo from the camera input joins the gallery picker's files" do
    sign_in(create_user("camera"))
    visit new_item_path

    gallery = find("#item_photos", visible: :all)
    assert gallery[:multiple], "the gallery picker still takes several photos"
    camera = find("#item_photo_camera", visible: :all)
    assert_equal "environment", camera[:capture]
    refute evaluate_script("arguments[0].hasAttribute('name')", camera), "the camera input uploads nothing itself"
    assert_selector "button", text: I18n.t("items.take_photo", locale: page_locale)

    attach_file "item_photo_camera", photo_path, make_visible: true

    assert wait_until { evaluate_script("document.getElementById('item_photos').files.length") == 1 },
           "the camera's photo did not reach the gallery input"
    assert_equal 0, evaluate_script("document.getElementById('item_photo_camera').files.length")
    assert_selector ".media-picker-preview img.media-picker-thumb", count: 1
  end

  private

  # A 2x2 PNG, written where the test can hand it to the browser.
  def photo_path
    path = Rails.root.join("tmp", "camera-#{SecureRandom.hex(3)}.png")
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    rows = ([ 0 ] + [ 200, 120, 40 ] * 2).pack("C*") * 2
    png = "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", [ 2, 2, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
          chunk.call("IDAT", Zlib::Deflate.deflate(rows)) + chunk.call("IEND", "")
    File.binwrite(path, png)
    path.to_s
  end
end
