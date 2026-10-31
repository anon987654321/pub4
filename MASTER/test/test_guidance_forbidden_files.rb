# frozen_string_literal: true

require_relative "test_helper"

# The forbidden basenames are written twice, as guidance an agent reads and as
# the constant the constitution enforces; this keeps the two the same list.
class TestGuidanceForbiddenFiles < Minitest::Test
  def test_forbidden_basenames_match_the_guidance_list
    guidance = Master.load_yaml(Master.data_path("guidance.yml")).dig("guidance", "anti_sprawl", "forbidden_files")
    assert_equal guidance.map(&:downcase).sort,
                 Master::Core::Constitution::FORBIDDEN_BASENAMES.sort
  end
end
