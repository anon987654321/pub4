# frozen_string_literal: true

require_relative "test_helper"

# A README is the operator-facing file, and it was the last to know.
#
# dilla's advertised FLYLO_DRUM_OVERLAY, FLYLO_TOP_DIRT and FLYLO_HAT_DUCK after
# `lib/` had renamed all three to WONKY_*, so operators were setting switches
# nothing read and getting the default render back with no error. Nothing
# measured the gap, because prose cannot fail.
#
# Every SCREAMING_SNAKE name a tree's README prints must appear somewhere in
# that tree's own source. Not a claim that it is an ENV var — the shape is what
# a reader will try to set, and a name in that shape that nothing reads is
# either renamed or gone.
class TestReadmeEnvNames < Minitest::Test
  REPO = File.expand_path("..", Master::ROOT)

  # tree => the files that count as "read somewhere in that tree".
  TREES = {
    "STUDIO/dilla" => ["dilla.rb", "lib/**/*.rb"],
    "MASTER" => ["lib/**/*.rb", "bin/*", "law/*.rb", "Rakefile", "data/*.yml"],
    "OPENBSD" => ["**/*.rb", "**/*.sh", "bin/*"],
  }.freeze

  # Not switches. MASTER's README shows a boot transcript, and the kernel string
  # in it is in the same shape as an ENV name without being one.
  NOT_A_SWITCH = %w[RELEASE_ARM64_T8112].freeze

  def test_every_screaming_snake_name_a_readme_prints_is_read_by_its_tree
    unread = TREES.flat_map do |tree, globs|
      readme = File.join(REPO, tree, "README.md")
      next [] unless File.file?(readme)

      source = read_all(File.join(REPO, tree), globs)
      names(File.read(readme)).reject { |name| source.include?(name) || built_by_interpolation?(name, source) }
                              .map { |name| "#{tree}/README.md: #{name}" }
    end

    assert_empty unread,
                 "a README names something its tree does not read — rename the doc or restore the reader:\n  " +
                 unread.join("\n  ")
  end

  # The harness must fail when a README goes stale, so it has to be seeing
  # names at all: a regex that matched nothing would pass forever.
  def test_the_harness_still_finds_names
    dilla = File.join(REPO, "STUDIO", "dilla", "README.md")
    skip "STUDIO/dilla/README.md is absent" unless File.file?(dilla)

    assert_operator names(File.read(dilla)).size, :>, 5,
                    "the name regex stopped matching — this test passes having read nothing"
  end

  private

  # A name can be read without being spelled. dilla builds a whole family from
  # one interpolation — `ENV["SONITEX_#{name.to_s.upcase}"]`, six sections — so
  # SONITEX_MIX is read by source that contains no such literal. That was the
  # first thing this test caught, and the test was the thing that was wrong.
  #
  # So a name also counts as read when any of its underscore-prefixes is
  # followed by an interpolation in the source. FLYLO_HAT_DUCK does not survive
  # that: nothing here writes FLYLO_#{ or FLYLO_HAT_#{, which is the difference
  # between a family and a rename.
  def built_by_interpolation?(name, source)
    parts = name.split("_")
    (1...parts.size).any? do |n|
      prefix = parts.first(n).join("_")
      source.include?("#{prefix}_\#{") || source.include?("#{prefix}\#{")
    end
  end

  def names(text)
    text.scan(/\b([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)\b/).flatten.uniq - NOT_A_SWITCH
  end

  def read_all(root, globs)
    Dir.glob(globs.map { |glob| File.join(root, glob) })
       .select { |path| File.file?(path) }
       .map { |path| File.read(path, encoding: "UTF-8").scrub }
       .join("\n")
  end
end
