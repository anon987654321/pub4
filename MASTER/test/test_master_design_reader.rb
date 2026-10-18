# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/master_design"

class MasterDesignReaderTest < Minitest::Test
  def test_rails_tools_path_forwards_to_the_shared_reader
    source = File.read(
      File.join(Master::ROOT, "tools", "rails", "operator", "master_design.rb"),
      encoding: "UTF-8",
    )

    assert_includes source, 'require_relative "../../master_design"'
    refute_match(/^\s*def (tokens_path|document|blocks|tokens|design_system|dig)\b/, source)
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
