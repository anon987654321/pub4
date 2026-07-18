# frozen_string_literal: true

require "test_helper"

class PostproJobTest < ActiveSupport::TestCase
  test "postpro script resolves to MASTER/tools/postpro/postpro.rb" do
    script = Shared::PostproProcessor.script
    assert script, "postpro script not found in #{Pub4::DeployPaths.postpro_candidates.map(&:expand_path)}"
    assert_includes script.to_s, "/MASTER/tools/postpro/postpro.rb"
    assert File.file?(script), "expected postpro at #{script}"
  end

  test "valid presets delegate to shared processor" do
    assert_equal Shared::PostproProcessor::VALID_PRESETS, PostproJob::VALID_PRESETS
  end
end
