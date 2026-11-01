# frozen_string_literal: true

require "minitest/autorun"

class PremergeInteractionCampaignContractTest < Minitest::Test
  SOURCE = File.expand_path("../../MASTER/tools/rails/premerge.rb", __dir__)

  def setup
    @source = File.read(SOURCE, encoding: "UTF-8")
  end

  def test_default_premerge_includes_the_interaction_campaign
    assert_includes @source, "else %i[apps pwa contracts coverage checks interactions]"
    assert_includes @source, "elsif ARGV.include?(\"--interactions\") then [:interactions]"
    assert_match(/system\(\*RUBY, runner, \"--all\", chdir: ROOT\)/, @source)
  end

  def test_incomplete_campaign_is_blocked_not_passed
    assert_match(/if exit_status == 3\s*\[BLOCKED, \"campaign is incomplete/, @source)
  end
end
