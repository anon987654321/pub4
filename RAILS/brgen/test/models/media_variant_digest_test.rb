# frozen_string_literal: true

require "test_helper"

# A pre-built variant is only found again if its digest matches the one the
# variant URL decodes to; the message verifier is JSON, so a Symbol value comes
# back a String and a :webp definition would be built twice.
class MediaVariantDigestTest < ActiveSupport::TestCase
  test "every declared variant digests the same after the URL round trip" do
    [ Post, Event, Story, Community, Place ].each do |model|
      model.media_variant_definitions.each do |attachment, variants|
        variants.each do |name, transformation|
          declared = ActiveStorage::Variation.new(transformation)
          decoded = ActiveStorage::Variation.decode(declared.key)
          assert_equal declared.digest, decoded.digest, "#{model}##{attachment} :#{name}"
        end
      end
    end
  end
end
