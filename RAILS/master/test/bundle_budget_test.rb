# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"
require "zlib"

# script/bundle_size.sh only printed sizes, so a face bundle could grow without
# anything failing. config/bundle_budgets.yml holds a gzip budget per bundle;
# this fails CI for a committed bundle over it, and proves the build script
# stops on one.
class BundleBudgetTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  BUDGETS = File.join(ROOT, "config", "bundle_budgets.yml")

  def budgets = YAML.safe_load_file(BUDGETS)

  def gzip_size(name) = Zlib.gzip(File.binread(File.join(ROOT, "public", name))).bytesize

  def report(path, root:)
    Open3.capture2e({ "ROOT" => root }, "sh", "-c", '. "$0"; report_bundle_size "$1"',
                    File.join(ROOT, "script", "bundle_size.sh"), path)
  end

  def test_the_heavy_face_bundles_have_budgets
    %w[three.face.module.js face_ascii.js face_vision.bundle.js].each do |name|
      assert_kind_of Integer, budgets[name], "#{name} has no gzip budget"
    end
  end

  def test_every_committed_bundle_is_within_its_budget
    budgets.each do |name, budget|
      size = gzip_size(name)
      assert_operator size, :<=, budget, "#{name} gzips to #{size} bytes, over its #{budget}-byte budget"
    end
  end

  def test_the_build_report_stops_on_a_bundle_over_budget
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "bundle_budgets.yml"), { "face_ascii.js" => 100 }.to_yaml)

      output, status = report(File.join(ROOT, "public", "face_ascii.js"), root: dir)
      refute status.success?, output
      assert_includes output, "over its 100-byte budget"

      output, status = report(File.join(ROOT, "public", "face_ascii.js"), root: ROOT)
      assert status.success?, output
      assert_includes output, "budget=#{budgets.fetch('face_ascii.js')}"
    end
  end
end
