# frozen_string_literal: true

require_relative "test_helper"

# Every path an entry-point script resolves at load time must exist on disk.
#
# This gate exists because `MASTER/bin/pub4` was dead on main for six days and nothing
# reported it. `5203c698e` deleted `lib/pub4/status_report.rb` as an orphan while
# `MASTER/bin/pub4` required it, so every subcommand -- including the `MASTER/bin/pub4
# status` CLAUDE.md documents as the repo-level check -- died with a LoadError
# before it parsed argv.
#
# The orphan sweep that deleted it was not careless; it was blind twice over, and
# both blindnesses are reproducible:
#
#   1. Extension filter. The sweep matched each file's innermost constant with a
#      grep over *.rb, *.yml and *.md. `MASTER/bin/pub4` has no extension, so its
#      `Pub4::StatusReport` call was invisible. Re-running that grep today still
#      returns zero callers for a constant that plainly has one.
#   2. Scope. The sweep ran from MASTER/, and `bin/pub4` puts MASTER/lib on the
#      load path itself rather than being required from anywhere the sweep read.
#
# So this checks the paths rather than the constants: it does not care how a
# file is referenced, only that what a runnable script asks for is on disk. A
# constant sweep can be fooled by an extension filter. A missing file cannot.
#
# Three forms, because the first version of this gate checked only the first and
# `3c17f848c` then broke the other two on the same day it moved `bin/` under
# `MASTER/`. A gate that covers one spelling of a defect does not cover the
# defect:
#
#   - `require "x/y"` against MASTER/lib
#   - `require_relative "../x/y"` against the script's own directory
#   - `File.join(ROOT, "bin", "ruby")` and friends -- a literal path built from a
#     root the script computes from `__dir__`. This is how `MASTER/bin/master`,
#     the surface CLAUDE.md names first, spent a day exiting `Errno::ENOENT` on
#     every invocation while `--help` still printed, because `--help` returns
#     before the exec.
class TestEntrypointRequires < Minitest::Test
  MASTER_ROOT = File.expand_path("..", __dir__)
  REPO_ROOT = File.expand_path("..", MASTER_ROOT)
  LIB = File.join(MASTER_ROOT, "lib")

  # A literal path a script builds but does not expect to find: it creates the
  # path itself before use. Each entry carries the reason, and the test below
  # fails if the path starts existing, so an exemption cannot outlive its
  # subject the way `data/` exemptions have.
  CREATED_AT_RUNTIME = {
    "MASTER/reports/cleanup" => "bin/cleanup FileUtils.mkdir_p's its own report directory",
  }.freeze

  # Top-level directories under MASTER/lib. A `require "x/y"` whose first segment
  # is one of these is ours and must resolve; anything else is stdlib or a gem
  # and is not this test's business.
  def internal_namespaces
    @internal_namespaces ||= Dir.children(LIB).select { |e| File.directory?(File.join(LIB, e)) }.to_set
  end

  def entrypoints
    Dir.glob(File.join(MASTER_ROOT, "bin", "*"))
       .select { |path| File.file?(path) && File.executable?(path) }
       .reject { |path| File.extname(path) == ".md" }
       .sort
  end

  def ruby_entrypoints
    entrypoints.filter_map do |script|
      source = File.read(script)
      [script, source] if source.start_with?("#!") && source.match?(/\bruby\b/)
    end
  end

  def relative(path) = path.delete_prefix("#{REPO_ROOT}/")

  def test_every_entrypoint_is_executable_and_present
    refute_empty entrypoints, "no executable entry points found -- the glob is wrong, not the tree"
  end

  def test_internal_requires_resolve
    missing = ruby_entrypoints.flat_map do |script, source|
      source.scan(/^\s*require\s+["']([^"']+)["']/).filter_map do |(feature)|
        next unless internal_namespaces.include?(feature.split("/").first)
        next if File.file?(File.join(LIB, "#{feature}.rb"))

        "#{relative(script)} requires #{feature.inspect}, but lib/#{feature}.rb does not exist"
      end
    end

    assert_empty missing, <<~MESSAGE
      An entry-point script requires a file that is not on disk. It will die with
      a LoadError before it runs. Restore the file or fix the require.

      #{missing.join("\n")}
    MESSAGE
  end

  def test_relative_requires_resolve
    missing = ruby_entrypoints.flat_map do |script, source|
      source.scan(/^\s*require_relative\s+["']([^"']+)["']/).filter_map do |(feature)|
        target = File.expand_path(feature, File.dirname(script))
        next if File.file?(target) || File.file?("#{target}.rb")

        "#{relative(script)} requires_relative #{feature.inspect}, " \
          "but #{relative(target)}.rb does not exist"
      end
    end

    assert_empty missing, <<~MESSAGE
      An entry-point script require_relative's a file that is not on disk. A
      require_relative resolves against the script's own directory, so moving the
      script breaks it even when the target never moved -- which is what happened
      when bin/ moved under MASTER/.

      #{missing.join("\n")}
    MESSAGE
  end

  # `exec`, `spawn` and `system` targets are built with File.join off a root the
  # script computes from __dir__. Resolving those roots is the only way to see a
  # path that moved out from under a literal.
  def test_literal_paths_built_from_a_computed_root_exist
    missing = ruby_entrypoints.flat_map do |script, source|
      literal_paths(script, source).filter_map do |path|
        rel = relative(path)
        # A glob is a query, not a path: matching nothing is an empty list, not a
        # crash, so it is not this gate's defect class.
        next if path.include?("*")
        next if File.exist?(path) || CREATED_AT_RUNTIME.key?(rel)

        "#{relative(script)} builds #{rel}, which does not exist"
      end
    end

    assert_empty missing, <<~MESSAGE
      An entry-point script builds a literal path that is not on disk. Nothing
      raises until the line runs, so the script can pass --help and still die on
      every real invocation.

      #{missing.join("\n")}
    MESSAGE
  end

  def test_runtime_created_exemptions_are_still_necessary
    live = CREATED_AT_RUNTIME.keys.select { |rel| File.exist?(File.join(REPO_ROOT, rel)) }

    assert_empty live, <<~MESSAGE
      A CREATED_AT_RUNTIME exemption names a path that now exists. Drop the entry
      -- an exemption that outlives its subject is a hole in a gate nobody can see.

      #{live.join("\n")}
    MESSAGE
  end

  # The specific regression, named, so a future orphan sweep that deletes it
  # again fails with the reason rather than a generic missing-file line.
  def test_bin_pub4_status_report_is_present
    assert_path_exists File.join(LIB, "pub4", "status_report.rb"),
                       "MASTER/bin/pub4 requires pub4/status_report and calls Pub4::StatusReport at :56. " \
                       "It is not an orphan. A constant grep filtered by file extension cannot see " \
                       "the caller, because MASTER/bin/pub4 has no extension."
  end

  private

  # Roots a script assigns from __dir__, then every File.join off one of them
  # whose segments are all string literals. A join with a variable segment names
  # a path only the run knows, and guessing at it produces a gate wrong in both
  # directions.
  def literal_paths(script, source)
    roots = source.scan(/^\s*([A-Z][A-Z0-9_]*)\s*=\s*File\.expand_path\(\s*"([^"]+)"\s*,\s*__dir__\s*\)/)
                  .to_h { |name, offset| [name, File.expand_path(offset, File.dirname(script))] }
    roots.keys.each do |name|
      derived = source.scan(/^\s*([A-Z][A-Z0-9_]*)\s*=\s*File\.join\(#{name},\s*"([^"]+)"\)$/)
      derived.each { |child, segment| roots[child] ||= File.join(roots[name], segment) }
    end
    return [] if roots.empty?

    names = Regexp.union(roots.keys)
    source.scan(/File\.join\((#{names}),\s*((?:"[^"]*"\s*,\s*)*"[^"]*")\s*\)/).map do |root, args|
      File.join(roots[root], *args.scan(/"([^"]*)"/).flatten)
    end.uniq
  end
end
