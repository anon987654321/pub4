# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "open3"

class StaticSyntaxSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_yaml_files_parse
    Dir.glob(File.join(ROOT, "data", "**", "*.yml")).each do |path|
      # Date and Time, because the house loader permits them
      # (Boot::Data.load_yaml). Without them this
      # asserted a stricter contract than any real reader uses and failed on
      # recovery/legacy_manifest.yml, which every reader loads fine.
      YAML.safe_load_file(path, aliases: true, permitted_classes: [Date, Time])
    rescue Psych::Exception => e
      flunk "YAML parse failed: #{path.sub(ROOT + '/', '')}: #{e.message}"
    end
  end

  # One `node --check` process per file, serially, was ~20s of process-spawn
  # against test_helper's 30s MASTER_TEST_TIMEOUT — green on an idle machine and
  # red whenever anything else was running, with the failure reported as
  # "Timeout::ExitException" from inside Open3 rather than as a syntax error,
  # which reads like broken JS. The cost is spawn latency, not parsing, and it
  # grows with every face module added to web/public. Spawning them in parallel
  # keeps the check byte-identical (still `node --check`, still one process per
  # file, same pass/fail per file) and brings a full run in well under the
  # budget.
  NODE_CHECK_CONCURRENCY = 8

  def test_visual_javascript_is_syntactically_valid
    skip "node not available" unless system("which node > /dev/null 2>&1")

    paths = Dir.glob(File.join(ROOT, "web", "public", "*.js"))
    return if paths.empty?

    slice = (paths.size / NODE_CHECK_CONCURRENCY.to_f).ceil
    failures = paths.each_slice(slice).map do |batch|
      Thread.new do
        batch.filter_map do |path|
          out, status = Open3.capture2e("node", "--check", path)
          "#{path.sub(ROOT + '/', '')}: #{out.lines.first&.strip}" unless status.success?
        end
      end
    end.flat_map(&:value)

    assert failures.empty?, "node --check failed:\n#{failures.join("\n")}"
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
