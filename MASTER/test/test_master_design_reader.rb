# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/master_design"

class MasterDesignReaderTest < Minitest::Test
  def test_retired_rails_tools_compatibility_path_remains_absent
    legacy = File.join(Master::ROOT, "tools", "rails", "operator", "master_design.rb")

    refute File.exist?(legacy), "remove the unreferenced legacy reader shim instead of recreating it"
  end

  def test_shared_reader_resolves_the_canonical_token_document
    previous = ENV["PUB4_RAILS_ROOT"]
    ENV.delete("PUB4_RAILS_ROOT")

    expected = File.join(Master::ROOT, "data", "tokens.yml")
    assert_equal expected, Operator::MasterDesign.tokens_path
    assert_kind_of Hash, Operator::MasterDesign.document.fetch("tokens")
  ensure
    previous.nil? ? ENV.delete("PUB4_RAILS_ROOT") : ENV["PUB4_RAILS_ROOT"] = previous
  end
end
