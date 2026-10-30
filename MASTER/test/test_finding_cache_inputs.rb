# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"

# FindingCache replays a law's findings while the file's text, the laws asked
# and FindingCache::SOURCES are unchanged. That is only sound if a cacheable law
# (one that does not declare reads_beyond_file?) reads nothing outside those
# inputs. A fresh process runs each cacheable law over small samples with File,
# IO and Dir watched, so a read is attributed to the law whose check made it; in
# this process an earlier test may already have made it.
#
# What it cannot see is data read once at boot and held in a constant:
# data/tokens.yml reaches CHOICE_OVERLOAD through Design::Thresholds that way,
# and was found by tracing every read of a booted process, not by this test.
class TestFindingCacheInputs < Minitest::Test
  PROBE = <<~'RUBY'
    $observed = nil
    watch = lambda do |reads|
      Module.new do
        reads.each do |name|
          define_method(name) do |*args, **opts, &block|
            $observed&.push([args.first.to_s, caller_locations(1, 6).join(" ")])
            super(*args, **opts, &block)
          end
        end
      end
    end
    File.singleton_class.prepend(watch.call(%i[read binread readlines foreach exist? file? stat open]))
    Dir.singleton_class.prepend(watch.call(%i[glob children entries each_child]))
    require "master"
    require "fix/scan/finding_cache"
    require "review/scan/law_tree"
    samples = { "lib/example.rb" => "class Example\n  def run(a, b)\n    puts a\n  end\nend\n",
                "app/views/example.html.erb" => "<div><p>hi</p></div>\n",
                "app/javascript/example.js" => "const a = 1;\n" }
    reads = Master::Review::Scan::LawTree.build.reject(&:reads_beyond_file?).to_h do |law|
      $observed = []
      samples.each do |relative, code|
        law.check(code, path: File.join(Master::ROOT, relative))
      rescue StandardError
        nil
      end
      seen = $observed
      $observed = nil
      [law.id.to_s, seen]
    end
    sources = Master::Fix::Scan::FindingCache::SOURCES
    puts JSON.generate("sources" => sources, "root" => Master::ROOT, "reads" => reads)
  RUBY

  # Not input: Ruby source (code loading), an executable looked up on PATH or
  # globbed for an interpreter, a linter binary's existence (a missing linter
  # reports a scan error, which the cache never keeps), and Ground::Swallow,
  # which writes. A probe for a file that does not exist yet, such as a nested
  # .rubocop.yml, is covered by its glob in SOURCES once it does.
  NOT_INPUT = %r{io/exec\.rb:\d+:in .*which|ruby_runner\.rb|ground/swallow\.rb|external_linter_laws\.rb.*linter_available}

  def probe
    lib = File.join(Master::ROOT, "lib")
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", PROBE, chdir: Master::ROOT)
    assert status.success?, err
    JSON.parse(out.lines.last)
  end

  def gaps(report)
    root = report.fetch("root")
    globs = report.fetch("sources").map { |glob| File.join(root, glob) }
    covered = ->(file) { globs.any? { |glob| File.fnmatch?(glob, file, File::FNM_PATHNAME) } }
    report.fetch("reads").filter_map do |id, reads|
      files = reads.reject do |file, from|
        code = file.end_with?(".rb") || File.directory?(file)
        file.empty? || code || file.start_with?(File.join(root, "app")) || from.match?(NOT_INPUT) || covered.call(file)
      end.map(&:first).uniq
      "#{id}: #{files.map { |file| file.delete_prefix("#{root}/") }.join(', ')}" unless files.empty?
    end
  end

  def test_no_cacheable_law_reads_a_file_outside_the_cache_key
    assert_empty gaps(probe), "declare reads_beyond_file? or add the file to FindingCache::SOURCES"
  end
end
