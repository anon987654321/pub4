# frozen_string_literal: true

# A gate whose scope is a path literal loses coverage without failing.
#
# Fix::SelfCheck and rake constitution scanned File.join(root, "lib"). core/ sat
# beside lib/ from 2026-07-20 to 2026-08-12, so the six files that judge every
# effect were the only files in the tree exempt from the law they enforce — and
# every gate stayed green throughout. The engines migration is the same defect:
# four scanners stopped seeing 57 views and the falling lint baseline read as
# improvement rather than blindness.
#
# data/scan_coverage.yml is the declaration; this is its reader's reader.

require "minitest/autorun"
require "yaml"
require_relative "../tools/scan_coverage"

class TestScanCoverage < Minitest::Test
  def self.report = @report ||= Pub4::ScanCoverage.run

  def setup
    @report = self.class.report
  end

  def test_every_ruby_tree_is_scanned_or_exempt_with_a_reason
    findings = @report["findings"].map { |row| "#{row['kind']}: #{row['dir']} — #{row['message']}" }

    assert_empty findings,
                 "add the directory to scan_coverage.roots, or to scan_coverage.exempt with the " \
                 "argument for exempting it:\n  #{findings.join("\n  ")}"
  end

  # The manifest is only worth anything if the gates read it. If this fails,
  # scan_coverage.yml has become the inert config it exists to prevent.
  def test_the_runtime_reads_the_manifest_rather_than_a_path_literal
    $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
    require "master"

    assert_equal Pub4::ScanCoverage.manifest["roots"], Master.scan_roots,
                 "Master.scan_roots disagrees with data/scan_coverage.yml"

    # Code, not comments: the first version of this assertion failed on the
    # comment in scan_dirs that names the literal it replaced, which is the
    # instrument being wrong rather than the code.
    code = File.readlines(File.expand_path("../lib/fix/self_check.rb", __dir__))
               .grep_v(/^\s*#/).join
    refute_includes code, 'File.join(@root, "lib")',
                    "SelfCheck went back to a hardcoded lib/ — that is the original defect"
  end

  # Coverage that silently drops to nothing passes every "no findings" check
  # there is. Assert the floor, not just the absence of failures.
  def test_the_scan_actually_reaches_the_runtime
    assert_operator @report["covered"].values.sum, :>, 300,
                    "the scanned roots hold #{@report['covered'].values.sum} files — " \
                    "coverage collapsed, which reads as a clean gate"
    assert_includes @report["covered"].keys, "lib"
  end

  # The fold spine is the specific thing that was exempt, so name it.
  def test_the_fold_spine_is_inside_a_scanned_root
    roots = Pub4::ScanCoverage.manifest["roots"]
    spine = ["lib/core.rb", *Dir.glob(File.expand_path("../lib/core/*.rb", __dir__)).map { |p| "lib/#{p.split('/lib/').last}" }]

    assert_operator spine.size, :>=, 6, "the fold spine glob matched #{spine.size} files"
    spine.each do |path|
      assert roots.any? { |root| path.start_with?("#{root}/") },
             "#{path} is outside every scanned root — the fold is exempt from its own law again"
    end
  end
end
