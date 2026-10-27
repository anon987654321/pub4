# frozen_string_literal: true

require_relative "test_helper"

class TestEffectAuditCoverage < Minitest::Test
  MASTER_ROOT = File.expand_path("..", __dir__)
  APPROVED_FOLD_ENTRYPOINTS = %w[
    lib/cli/core_bridge.rb
    lib/cli/core_command.rb
  ].freeze

  def test_every_production_fold_entrypoint_installs_the_strict_effect_observer
    production_sources = Dir.glob(File.join(MASTER_ROOT, "lib/**/*.rb")) +
                         [File.join(MASTER_ROOT, "bin", "master")]
    callsites = production_sources.select do |path|
      File.read(path, encoding: "UTF-8").match?(/Master::Core::Fold\.new\s*\(/)
    end.map { |path| path.delete_prefix("#{MASTER_ROOT}/") }.sort

    assert_equal APPROVED_FOLD_ENTRYPOINTS, callsites,
                 "new direct Fold entrypoints need explicit lifecycle-audit review"

    callsites.each do |relative|
      source = File.read(File.join(MASTER_ROOT, relative), encoding: "UTF-8")
      assert_includes source, "Master::Trace::EffectObserver.new",
                       "#{relative} must create a strict effect observer"
      assert_match(/effect_observer\s*:/, source,
                   "#{relative} must pass the observer into Fold")
    end
  end
end
