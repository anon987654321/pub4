# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "open3"

class StaticSyntaxSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_yaml_files_parse
    Dir.glob(File.join(ROOT, "data", "**", "*.yml")).each do |path|
      YAML.safe_load_file(path, aliases: true)
    rescue Psych::Exception => e
      flunk "YAML parse failed: #{path.sub(ROOT + '/', '')}: #{e.message}"
    end
  end

  def test_visual_javascript_is_syntactically_valid
    skip "node not available" unless system("which node > /dev/null 2>&1")

    Dir.glob(File.join(ROOT, "web", "public", "*.js")).each do |path|
      _out, status = Open3.capture2e("node", "--check", path)
      assert status.success?, "node --check failed: #{path.sub(ROOT + '/', '')}"
    end
  end

  def test_executable_bins_have_ruby_shebang
    Dir.glob(File.join(ROOT, "bin", "*")).each do |path|
      next unless File.file?(path)
      next if path.end_with?(".md")

      first = File.open(path, &:readline)
      assert_match(/ruby|sh|bash|zsh/, first, path)
    end
  end
end
