# frozen_string_literal: true

require_relative "test_helper"

# The deterministic autofix stage is held to what it did on 2026-10-12: 105 files
# changed before any model ran, a nested ternary rewritten into an unindented
# `if` that turned the ASCII face's golden frame red, and whitespace edits to
# laws.yml and tokens.yml. Every case here drives the real guard against a
# temporary tree; no lane, no RuboCop run, no model.
class TestAutofixGuard < Minitest::Test
  Guard = Master::Fix::AutofixGuard

  def setup
    Master::Fix::Scan::MechanicalAutofix # loads ast_fixer.rb, which Zeitwerk cannot autoload by name
    Guard.reset!
    @env = ENV.to_h.slice("MASTER_AUTOFIX_MODE", "MASTER_AUTOFIX_MAX_FILES")
  end

  def teardown
    Guard.reset!
    %w[MASTER_AUTOFIX_MODE MASTER_AUTOFIX_MAX_FILES].each { |key| ENV.delete(key) }
    @env.each { |key, value| ENV[key] = value }
  end

  def test_the_rendered_and_irreplaceable_paths_are_protected
    %w[
      /r/MASTER/lib/cli/face/ascii.rb
      /r/MASTER/lib/voice/policy.rb
      /r/MASTER/lib/io/local_tts.rb
      /r/MASTER/data/tokens.yml
      /r/STUDIO/dilla/dilla.rb
      /r/STUDIO/postpro/constitution.rb
      /r/MASTER/test/fixtures/golden_frame.txt
      /r/MASTER/test/golden/frame.rb
    ].each { |path| refute_nil Guard.protected_reason(path), "#{path} was not protected" }
  end

  def test_ordinary_source_is_not_protected
    assert_nil Guard.protected_reason("/r/MASTER/lib/fix/repair_loop.rb")
    assert_nil Guard.protected_reason("/r/RAILS/brgen/app/models/post.rb")
  end

  def test_law_catalogue_is_not_refused_by_path_alone
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER", "data"))
      File.write(File.join(root, "MASTER", "data", "soul.yml"),
                 "absolute:\n  sacred_paths:\n    - lib/ground/pledge.rb\n")
      laws = File.join(root, "MASTER", "data", "laws.yml")
      File.write(laws, "law_catalogue: {}\n")

      assert_nil Guard.admit(laws, root:)
      assert_equal "law_catalogue: {}\n", File.read(laws)
      assert_empty Guard.refused
    end
  end

  def test_a_sibling_tree_is_not_sacred_when_the_run_is_rooted_at_master
    Dir.mktmpdir do |repo|
      master = File.join(repo, "MASTER")
      FileUtils.mkdir_p(File.join(master, "data"))
      File.write(File.join(master, "data", "soul.yml"), "absolute:\n  sacred_paths:\n    - data/\n")

      assert_nil Guard.protected_reason(File.join(repo, "RAILS", "brgen_dating", "app", "controllers", "dating", "base_controller.rb"), root: master)
      refute_nil Guard.protected_reason(File.join(master, "data", "laws.yml"), root: master)
    end
  end

  def test_a_candidate_that_does_not_parse_is_refused
    assert_match(/does not parse/, Guard.candidate_reason("a.rb", "x = 1\n", "def broken(\n"))
    assert_match(/does not parse/, Guard.candidate_reason("a.yml", "a: 1\n", "a: [1,\n"))
    assert_match(/does not parse/, Guard.candidate_reason("a.json", "{}", "{"))
    assert_nil Guard.candidate_reason("a.rb", "x = 1 \n", "x = 1\n")
  end

  def test_whitespace_only_edits_to_data_are_never_applied
    assert_match(/whitespace-only/, Guard.candidate_reason("laws.yml", "a:   1\n", "a: 1\n"))
    assert_match(/whitespace-only/, Guard.candidate_reason("t.json", "{ \"a\": 1 }", "{\"a\":1}"))
    assert_nil Guard.candidate_reason("laws.yml", "a: 1\n", "a: 2\n")
  end

  def test_the_cap_holds_back_the_rest_and_reports_them
    ENV["MASTER_AUTOFIX_MAX_FILES"] = "2"
    assert_nil Guard.admit("/r/a.rb")
    Guard.note_written("/r/a.rb")
    Guard.note_written("/r/b.rb")

    assert_nil Guard.admit("/r/a.rb"), "a file already written stays admitted"
    assert_match(/cap of 2/, Guard.admit("/r/c.rb"))
    assert_equal ["/r/c.rb"], Guard.capped
    assert(Guard.summary_lines.any? { |line| line.include?("held back (cap), /r/c.rb") })
  end

  def test_mode_off_admits_nothing_and_a_bad_mode_is_refused
    Guard.mode = "off"
    assert_equal "autofix is off", Guard.admit("/r/a.rb")
    assert_raises(ArgumentError) { Guard.mode = "maybe" }
  end

  def test_the_mapped_test_is_the_nearest_test_named_for_the_file
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p([File.join(root, "lib"), File.join(root, "test")])
      File.write(File.join(root, "lib", "thing.rb"), "")
      assert_nil Guard.mapped_test(File.join(root, "lib", "thing.rb"))

      File.write(File.join(root, "test", "test_thing.rb"), "")
      assert_equal File.join(root, "test", "test_thing.rb"), Guard.mapped_test(File.join(root, "lib", "thing.rb"))
    end
  end

  Candidate = Struct.new(:changed, :content, :transforms)

  def suite(root, expected)
    FileUtils.mkdir_p([File.join(root, "lib"), File.join(root, "test")])
    lib = File.join(root, "lib", "thing.rb")
    File.write(lib, "# frozen_string_literal: true\n\nTHING = \"a\"\n")
    File.write(File.join(root, "test", "test_thing.rb"), <<~RUBY)
      require "minitest/autorun"
      require_relative "../lib/thing"
      class TestThing < Minitest::Test
        def test_value = assert_equal #{expected.inspect}, THING
      end
    RUBY
    lib
  end

  def autofix(root) = Master::Fix::Scan::MechanicalAutofix.new(scanner: nil, root:, dirty: ->(_) { false }, write_guard: PassingGuard.new)

  class PassingGuard
    def verdict(path:, content:) = Master::Fix::WriteGuard::Verdict.new(introduced: [])
  end

  # The ascii.rb case: a rewrite that parses, passes every scanner and turns
  # the file's own golden test red. The bytes must come back.
  def test_a_write_that_turns_the_mapped_test_red_is_put_back
    Dir.mktmpdir do |root|
      lib = suite(root, "a")
      bad = Candidate.new(true, "# frozen_string_literal: true\n\nTHING = \"b\"\n", [:fixture])

      Master::Fix::Scan::AstFixer.stub(:propose, bad) do
        outcome = autofix(root).rewrite(lib, File.read(lib))

        assert_equal :refused, outcome.status
        assert_match(/test_thing.rb failed/, outcome.reason)
      end
      assert_includes File.read(lib), 'THING = "a"'
      assert_empty Guard.written
    end
  end

  def test_a_write_whose_mapped_test_stays_green_lands
    Dir.mktmpdir do |root|
      lib = suite(root, "a")
      good = Candidate.new(true, "# frozen_string_literal: true\n\nTHING = \"a\" # kept\n", [:fixture])

      Master::Fix::Scan::AstFixer.stub(:propose, good) do
        assert_equal :written, autofix(root).rewrite(lib, File.read(lib)).status
      end
      assert_equal [lib], Guard.written
    end
  end

  def test_a_candidate_that_does_not_parse_never_reaches_the_file
    Dir.mktmpdir do |root|
      lib = suite(root, "a")
      broken = Candidate.new(true, "THING = (\n", [:fixture])

      Master::Fix::Scan::AstFixer.stub(:propose, broken) do
        assert_equal :refused, autofix(root).rewrite(lib, File.read(lib)).status
      end
      assert_includes File.read(lib), 'THING = "a"'
    end
  end

  def test_dry_mode_writes_a_patch_and_leaves_the_file
    Dir.mktmpdir do |root|
      lib = suite(root, "a")
      good = Candidate.new(true, "# frozen_string_literal: true\n\nTHING = \"a\" # kept\n", [:fixture])
      Guard.mode = "dry"

      Master::Fix::Scan::AstFixer.stub(:propose, good) do
        assert_equal :unchanged, autofix(root).rewrite(lib, File.read(lib)).status
      end
      assert_equal "# frozen_string_literal: true\n\nTHING = \"a\"\n", File.read(lib)
      patch = File.read(Guard.patch_path(root))
      assert_includes patch, "+THING = \"a\" # kept"
      assert_includes patch, "lib/thing.rb"
    end
  end

  def test_protected_files_are_not_opened_by_the_writer
    Dir.mktmpdir do |root|
      face = File.join(root, "MASTER", "lib", "cli", "face", "ascii.rb")
      FileUtils.mkdir_p(File.dirname(face))
      File.write(face, "x = 1  \n")

      outcome = autofix(root).rewrite(face, File.read(face))

      assert_equal :unchanged, outcome.status
      assert_equal "x = 1  \n", File.read(face)
    end
  end

  # RuboCop's own correction of a nested ternary produced the unindented `if`
  # that broke the golden frame, so the cop only detects now.
  def test_rubocop_does_not_autocorrect_a_nested_ternary
    config = YAML.safe_load_file(File.join(Master::ROOT, ".rubocop.yml"))

    assert_equal false, config.dig("Style/NestedTernaryOperator", "AutoCorrect")
    assert_equal true, config.dig("Style/NestedTernaryOperator", "Enabled")
  end
end
