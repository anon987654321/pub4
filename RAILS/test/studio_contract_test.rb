# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../MASTER/contracts/studio"

class StudioContractTest < Minitest::Test
  def test_photograph_contract_reads_structured_result
    Dir.mktmpdir do |root|
      File.write(File.join(root, "photograph.rb"), <<~RUBY)
        # frozen_string_literal: true
        puts JSON.generate("still" => "/tmp/still.jpg")
      RUBY

      original = ENV["PUB4_STUDIO_ROOT"]
      ENV["PUB4_STUDIO_ROOT"] = root
      assert_equal({ "still" => "/tmp/still.jpg" }, Contracts::Studio.photograph(prompt: "test"))
    ensure
      ENV["PUB4_STUDIO_ROOT"] = original
    end
  end

  def test_canonical_media_entrypoints_are_addressable
    assert Contracts::Studio.photograph_script
    assert Contracts::Studio.dilla_script
    assert Contracts::Studio.postpro_script
    assert Contracts::Studio.replicate_script
  end
end
