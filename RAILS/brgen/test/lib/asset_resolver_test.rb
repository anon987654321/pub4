# frozen_string_literal: true

require "test_helper"

# vm23 runs the suite in an app copy that still holds the last release's
# public/assets. Propshaft resolves through that manifest whenever it exists, so
# assets added since then were "not found in the load path" in every test.
class AssetResolverTest < ActiveSupport::TestCase
  test "tests read assets from the load path, not a deploy's precompiled manifest" do
    refute_equal Rails.root.join("public/assets/.manifest.json"), Rails.application.config.assets.manifest_path
    assert_kind_of Propshaft::Resolver::Dynamic, Rails.application.assets.resolver
  end
end
