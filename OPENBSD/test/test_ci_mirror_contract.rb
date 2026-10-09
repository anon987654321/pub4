# frozen_string_literal: true

require "minitest/autorun"

# vps_ci.sh runs RAILS/__shared/config/ci.rb against a mirror at
# /home/<app>/pub4-rails that holds only the MASTER pieces it names. A MASTER
# tool that gains a require_relative outside that set fails on the box with a
# LoadError (design_tokens -> lib/trace/dmesg, 2026-10-09) and nowhere else,
# because the checkout has everything. This resolves the literal require_relative
# graph of every tool ci.rb runs, statically, and asserts each file is mirrored.
class CiMirrorContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CI = File.read(File.join(ROOT, "RAILS", "__shared", "config", "ci.rb"), encoding: "UTF-8")
  SYNC = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_ci.sh"), encoding: "UTF-8")
  LITERAL = /^\s*require_relative\s+["']([^"'#]+)["']/

  # Whole directories the sync archives, plus the files it names one by one.
  def mirrored_trees
    %w[MASTER/tools MASTER/lib/operator]
  end

  def mirrored_files
    list = SYNC[/local -a lib_files=\(([^)]*)\)/m, 1]
    refute_nil list, "lib_files not found in vps_ci.sh -- the scan broke, not the sync"
    list.split + ["MASTER/data/laws.yml"]
  end

  def mirrored?(rel)
    mirrored_files.include?(rel) || mirrored_trees.any? { |tree| rel.start_with?("#{tree}/") }
  end

  def ci_tools
    names = CI[/%w\[\s*(.*?)\s*\]\.each/m, 1].split
    refute_empty names
    roots = %w[MASTER/tools MASTER/tools/rails/operator]
    lints = names.map do |name|
      roots.map { |r| "#{r}/#{name}.rb" }.find { |p| File.file?(File.join(ROOT, p)) } or flunk("#{name}.rb is in no tool root")
    end
    lints + %w[MASTER/tools/rails/build_all_css.rb MASTER/tools/rails/operator/ci_guard.rb
               MASTER/tools/rails/operator/dmesg.rb]
  end

  def closure(starts)
    seen = {}
    queue = starts.dup
    until queue.empty?
      rel = queue.shift
      next if seen[rel]

      seen[rel] = true
      File.readlines(File.join(ROOT, rel), encoding: "UTF-8").each do |text|
        match = text.match(LITERAL) or next
        target = File.expand_path(match[1], File.dirname(File.join(ROOT, rel)))
        target += ".rb" unless File.file?(target)
        queue << target.delete_prefix("#{ROOT}/") if File.file?(target)
      end
    end
    seen.keys
  end

  def test_the_tools_ci_runs_are_found
    assert_includes ci_tools, "MASTER/tools/rhythm_lint.rb"
    assert_includes ci_tools, "MASTER/tools/rails/operator/fallback_drift_lint.rb"
  end

  def test_every_required_file_is_in_the_mirror
    missing = closure(ci_tools).reject { |rel| mirrored?(rel) }
    assert_empty missing, "vps_ci.sh sync_ci_rails_root must mirror these (add to lib_files)"
  end

  def test_every_named_mirror_file_exists
    gone = mirrored_files.reject { |rel| File.file?(File.join(ROOT, rel)) }
    assert_empty gone
  end
end
