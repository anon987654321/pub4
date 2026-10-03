# frozen_string_literal: true

require_relative "test_helper"
require "rake"

class TestToolEntrypoints < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  RAKEFILE = File.join(ROOT, "Rakefile")

  def test_every_rake_declared_tool_file_exists
    source = File.read(RAKEFILE, encoding: "UTF-8")
    paths = source.scan(%r{["'](tools/[^"']+\.rb)["']}).flatten.uniq.sort

    refute_empty paths
    missing = paths.reject { |path| File.file?(File.join(ROOT, path)) }
    assert_empty missing, "Rakefile references missing tool file(s): #{missing.join(', ')}"
  end

  def test_flattened_tool_shelves_are_not_recreated
    expected = %w[
      tools/master_design.rb
      tools/scss_rules.rb
      tools/frontend_rule_set.rb
      tools/postpro/frame_set.rb
      tools/postpro/rescue.rb
      tools/postpro/uncanny.rb
      tools/replicate/chain.rb
      tools/replicate/craft.rb
      tools/replicate/schema_snapshot.rb
    ]
    missing = expected.reject { |path| File.file?(File.join(ROOT, path)) }
    assert_empty missing, "flattened tool file(s) missing: #{missing.join(', ')}"

    retired = %w[tools/design tools/postpro/lib tools/replicate/lib]
    present = retired.select { |path| Dir.exist?(File.join(ROOT, path)) }
    assert_empty present, "retired tool shelf(s) remain: #{present.join(', ')}"
  end
end
