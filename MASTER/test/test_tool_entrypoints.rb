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
    # A test-file glob such as tools/test/test_*.rb is declared, not a file: it
    # must match at least one.
    missing = paths.reject { |path| Dir.glob(File.join(ROOT, path)).any? { |hit| File.file?(hit) } }
    assert_empty missing, "Rakefile references missing tool file(s): #{missing.join(', ')}"
  end

  def test_shared_css_and_frontend_policy_paths_use_canonical_names
    scss_parser = File.join(ROOT, "lib", "fix", "scss_parser.rb")
    old_scss_path = File.join(ROOT, "lib", "fix", "scss_rules.rb")
    assert File.file?(scss_parser), "SCSS syntax parser is missing"
    refute File.exist?(old_scss_path), "retired rules-named parser path returned"

    repo_root = File.expand_path("../..", __dir__)
    source = File.join(ROOT, "tools", "frontend_law_set.rb")
    projection = File.join(repo_root, "RAILS", "__shared", "app", "services", "shared", "frontend_law_set.rb")
    retired_projection = File.join(repo_root, "RAILS", "__shared", "app", "services", "shared", "frontend_rule_set.rb")

    assert_match(/class FrontendLawSet/, File.read(source))
    assert_match(/class FrontendLawSet/, File.read(projection))
    refute File.exist?(retired_projection), "retired rules-named projection path returned"
  end

  def test_flattened_tool_shelves_are_not_recreated
    expected = %w[
      tools/master_design.rb
      tools/scss.rb
      tools/frontend_law_set.rb
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
