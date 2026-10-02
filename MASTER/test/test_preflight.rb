# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestPreflight < Minitest::Test
  def test_reports_ruby_syntax_errors_without_loading_the_file
    Dir.mktmpdir do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "def broken(\n")

      findings = Master::Fix::Preflight.new(root:).findings([path])

      assert_equal 1, findings.size
      assert_equal "PREFLIGHT", findings.first[:rule]
      assert_equal :critical, findings.first[:severity]
      assert_match(/Ruby syntax error/, findings.first[:message])
    end
  end

  def test_reports_yaml_parse_errors
    Dir.mktmpdir do |root|
      path = File.join(root, "broken.yml")
      File.write(path, "one: [two\n")

      findings = Master::Fix::Preflight.new(root:).findings([path])

      assert_equal 1, findings.size
      assert_equal "PREFLIGHT", findings.first[:rule]
      assert_match(/YAML parse error/, findings.first[:message])
    end
  end

  def test_skips_generated_paths
    Dir.mktmpdir do |root|
      path = File.join(root, "web", "public", "face.runtime.js")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "not ruby\n")

      assert_empty Master::Fix::Preflight.new(root:).findings([path])
    end
  end
  def test_named_ruby_entrypoints_use_ruby_preflight
    Dir.mktmpdir do |root|
      ["Gemfile", "Rakefile", "config.ru"].each do |name|
        path = File.join(root, name)
        File.write(path, "task :ok do\nend\n")
        assert_empty Master::Fix::Preflight.new(root:).findings([path]), name
      end

      path = File.join(root, "Gemfile")
      File.write(path, "if true\n")
      assert_match(/Ruby syntax error/, Master::Fix::Preflight.new(root:).findings([path]).first[:message])
    end
  end
end
