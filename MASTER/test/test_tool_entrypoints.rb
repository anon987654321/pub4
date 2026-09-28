# frozen_string_literal: true

require_relative "test_helper"
require "rake"

class TestToolEntrypoints < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  RAKEFILE = File.join(ROOT, "Rakefile")

  def test_every_rake_declared_tool_file_exists
    source = File.read(RAKEFILE, encoding: "UTF-8")
    paths = source.scan(/["'](tools/[^"']+\.rb)["']/).flatten.uniq.sort

    refute_empty paths
    missing = paths.reject { |path| File.file?(File.join(ROOT, path)) }
    assert_empty missing, "Rakefile references missing tool file(s): #{missing.join(', ')}"
  end
end
