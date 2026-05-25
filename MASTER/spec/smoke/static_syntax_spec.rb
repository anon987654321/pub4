# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class StaticSyntaxSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_yaml_files_parse
    Dir.glob(File.join(ROOT, "data", "**", "*.yml")).each do |path|
      YAML.safe_load_file(path, aliases: true)
    rescue Psych::Exception => e
      flunk "YAML parse failed: #{path.sub(ROOT + '/', '')}: #{e.message}"
    end
  end

  def test_visual_javascript_has_balanced_common_delimiters
    Dir.glob(File.join(ROOT, "web", "public", "*.js")).each do |path|
      source = File.read(path)
      assert_equal source.count("("), source.count(")"), path
      assert_equal source.count("{"), source.count("}"), path
      assert_equal source.count("["), source.count("]"), path
    end
  end

  def test_executable_bins_have_ruby_shebang
    Dir.glob(File.join(ROOT, "bin", "*")).each do |path|
      next unless File.file?(path)
      first = File.readline(path)
      assert_match(/ruby|sh|bash/, first, path)
    end
  end
end
