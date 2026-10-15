# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class TestDillaOutputPathCli < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "dilla", "dilla.rb")

  def invoke(*arguments, environment: {})
    environment = { "DILLA_OUTPUT_DIR" => nil, "XDG_DATA_HOME" => nil }.merge(environment)

    Open3.capture3(
      environment,
      RbConfig.ruby,
      SCRIPT,
      "output-path",
      *arguments,
      chdir: ROOT
    )
  end

  def test_reference_root_uses_the_configured_absolute_data_home
    Dir.mktmpdir do |dir|
      data_home = File.join(dir, "xdg-data")
      stdout, stderr, status = invoke(
        "reference-root",
        environment: { "XDG_DATA_HOME" => data_home }
      )

      assert status.success?, "output-path failed: #{stderr}"
      assert_equal "#{File.join(data_home, "dilla-references")}\n", stdout
      assert_empty stderr
    end
  end

  def test_render_directory_uses_the_timestamp_in_utc
    Dir.mktmpdir do |dir|
      data_home = File.join(dir, "xdg-data")
      stdout, stderr, status = invoke(
        "dilla-render-directory",
        "2026-01-02T00:30:00+02:00",
        environment: { "XDG_DATA_HOME" => data_home }
      )

      expected = File.join(data_home, "dilla-renders", "2026-01-01")
      assert status.success?, "output-path failed: #{stderr}"
      assert_equal "#{expected}\n", stdout
      assert_empty stderr
    end
  end

  def test_explicit_dilla_output_directory_overrides_the_default
    Dir.mktmpdir do |dir|
      override = File.join(dir, "operator-chosen")
      stdout, stderr, status = invoke(
        "dilla-render-directory",
        "2026-01-02T00:00:00Z",
        environment: {
          "XDG_DATA_HOME" => File.join(dir, "xdg-data"),
          "DILLA_OUTPUT_DIR" => override
        }
      )

      assert status.success?, "output-path failed: #{stderr}"
      assert_equal "#{override}\n", stdout
      assert_empty stderr
    end
  end

  def test_missing_render_timestamp_fails_visibly_without_a_path
    stdout, stderr, status = invoke("dilla-render-directory")

    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_match(/requires one ISO 8601 timestamp/, stderr)
  end

  def test_unknown_output_path_kind_fails_visibly_without_a_path
    stdout, stderr, status = invoke("not-a-real-path")

    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_match(/unknown output path/, stderr)
  end
end
