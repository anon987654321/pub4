# frozen_string_literal: true

require_relative "test_helper"
require "ripper"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/operator/snapshot_pack"
require_relative "../tools/snapshot"

# The snapshot is the copy of a tree that fits another model's context. It may drop what a
# reader does not need, and must never change what Ruby means.
class TestSnapshotPack < Minitest::Test
  Pack = Operator::SnapshotPack
  Map = Operator::SnapshotMap

  RUBY = <<-'RB'
#!/usr/bin/env ruby
# frozen_string_literal: true

# Fetches a page and returns its text.
# A second comment line that is dropped.

require "net/http"

module Fetch
  # explains the method
  def self.call(url) # trailing note
    text = <<~TXT
      # not a comment, it is heredoc text

      kept blank line above
    TXT
    puts "# also not a comment" if url

=begin
block comment
=end
    text
  end
end
  RB

  def code_tokens(source)
    Ripper.lex(source).reject { |_, type, _, _| %i[on_comment on_sp on_nl on_ignored_nl on_embdoc_beg on_embdoc on_embdoc_end].include?(type) }
          .map { |_, type, tok, _| [type, tok.strip] }.reject { |_, tok| tok.empty? }
  end

  def test_ruby_loses_comments_and_blank_lines_but_not_a_single_code_token
    out = Pack.minify("a.rb", RUBY)

    refute_includes out, "A second comment line"
    refute_includes out, "explains the method"
    refute_includes out, "trailing note"
    refute_includes out, "block comment"
    refute_includes out, "frozen_string_literal"
    assert_equal code_tokens(RUBY), code_tokens(out), "only comments and whitespace may change"
    assert Ripper.sexp(out), "the result must still parse"
  end

  def test_text_inside_a_heredoc_or_a_string_is_left_exactly_alone
    out = Pack.minify("a.rb", RUBY)

    assert_includes out, "# not a comment, it is heredoc text"
    assert_includes out, %(puts "# also not a comment" if url)
    assert_includes out, "text = <<~TXT\n      # not a comment, it is heredoc text\n\n      kept blank line above\n    TXT"
  end

  def test_the_first_comment_survives_as_a_one_line_purpose_after_the_shebang
    lines = Pack.minify("a.rb", RUBY).lines

    assert_equal "#!/usr/bin/env ruby\n", lines[0]
    assert_equal "# Fetches a page and returns its text.\n", lines[1]
  end

  def test_a_ruby_file_that_does_not_parse_is_not_rewritten_beyond_whitespace
    broken = "def a(\n  # a comment\n  x\n\n"

    assert_includes Pack.minify("a.rb", broken), "# a comment"
  end

  def test_other_formats_lose_only_their_comments
    assert_equal "a: 1\n", Pack.minify("x.yml", "a: 1\n\n").sub(/\A# .*\n/, "")
    refute_includes Pack.minify("x.yml", "# one\na: 1 # kept inline\n# two\nb: 2\n"), "# two"
    assert_equal "{\"a\":[1,2]}\n", Pack.minify("x.json", "{\n  \"a\": [1,\n 2]\n}\n")
    assert_equal "const a = 1;\n", Pack.minify("x.js", "// note\n/* block\n   more */\nconst a = 1;\n\n")
    assert_equal "a {\nb: c\n}\n", Pack.minify("x.css", "/* c */\na {\n  b: c\n}\n")
    assert_equal "#!/bin/sh\n# Does a thing.\nls\n", Pack.minify("run", "#!/bin/sh\n# Does a thing.\n\n# gone\nls\n")
  end

  def test_what_carries_no_reading_value_is_omitted_and_why
    assert_equal "lockfile", Pack.omit_reason("RAILS/package-lock.json")
    assert_equal "lockfile", Pack.omit_reason("MASTER/Gemfile.lock")
    assert_equal "vendored library", Pack.omit_reason("RAILS/master/public/three.face.module.js")
    assert_equal "generated bundle", Pack.omit_reason("RAILS/master/public/face_vision.bundle.js")
    assert_equal "stored layout snapshots", Pack.omit_reason("MASTER/checks/data/layout_snapshots/a-b.json")
    assert_nil Pack.omit_reason("MASTER/lib/fix/fix_loop.rb")
  end

  def test_the_map_names_each_file_with_its_purpose_and_declarations
    original = "# Reads the ledger.\nmodule Ledger\n  def read\n  end\n  def write\n  end\nend\n"
    line = Map.map_line({ path: "lib/ledger.rb", original:, minified: Pack.minify("lib/ledger.rb", original) })

    assert_equal "ledger.rb [7L] — Reads the ledger. | Ledger: read write", line
  end

  def file(path, bytes, inlinable: true) = { path:, block: "x" * bytes, inlinable: }

  def test_the_budget_goes_to_the_constitution_and_entry_points_first_then_small_files_then_tests_last
    files = [
      file("T/test/t_test.rb", 100), file("T/lib/big.rb", 900), file("T/lib/a/small.rb", 100),
      file("T/bin/run", 200), file("T/README.md", 300), file("T/lib/top.rb", 150)
    ]

    assert_equal %w[T/README.md T/bin/run T/lib/top.rb T/lib/a/small.rb T/lib/big.rb T/test/t_test.rb].sort,
                 Pack.choose(files, 10_000).to_a.sort
    chosen = Pack.choose(files, 700)
    assert_includes chosen, "T/README.md"
    assert_includes chosen, "T/bin/run"
    refute_includes chosen, "T/lib/big.rb", "a file that no longer fits is left to the map"
    refute_includes chosen, "T/test/t_test.rb", "tests come last, after the room is gone"
  end

  def test_a_file_that_others_mention_is_ranked_ahead_of_one_nothing_mentions
    files = [
      { path: "T/lib/hub.rb", minified: "class Hub\nend\n" },
      { path: "T/lib/leaf.rb", minified: "class Leaf\n  Hub.call\nend\n" },
      { path: "T/lib/other.rb", minified: "Hub.call\nLeaf.call\n" },
      { path: "T/data/x.yml", minified: "a: 1\n" },
    ]

    ranked = Pack.rank_centrality(files).to_h { |f| [f[:path], f[:centrality]] }

    assert_equal 2, ranked["T/lib/hub.rb"], "two other files name Hub"
    assert_equal 1, ranked["T/lib/leaf.rb"]
    assert_equal 0, ranked["T/data/x.yml"], "only Ruby files carry a constant to count"
  end

  def test_a_file_over_the_cap_and_a_test_are_never_inlined_whatever_the_room
    files = [file("T/lib/huge.rb", 100, inlinable: false), file("T/lib/ok.rb", 100)]

    assert_equal ["T/lib/ok.rb"], Pack.choose(files, 1_000_000).to_a
  end

  def test_a_test_file_appears_in_the_map_by_name_only
    original = "class FooTest\n  def test_a\n  end\nend\n"

    file = { path: "T/test/foo_test.rb", original:, minified: original }

    assert_equal "foo_test.rb [4L]", Map.map_line(file)
    assert_equal "~foo_test.rb [4L]", Map.map_line(file, inlined: false)
  end

  def test_reading_pack_integrity_detects_truncation_and_changed_source
    Dir.mktmpdir do |repo|
      Thread.current[:snapshot_repo] = repo
      FileUtils.mkdir_p(File.join(repo, "DEMO/lib"))
      File.write(File.join(repo, "DEMO/lib/a.rb"), "# A sample.\nputs 1\n")

      Pack.write(Host, "DEMO", io: StringIO.new)
      text = File.read(File.join(repo, "snapshot_DEMO.md"))

      assert Pack.verify_text(text), "a complete reading pack verifies"
      assert_includes text, "## END OF PACK\nsha256="
      assert_match(/SHA-256 \(normalized source\): [0-9a-f]{64}/, text)
      refute Pack.verify_text(text.sub("puts 1", "puts 2")), "changed source must fail the pack digest"
      refute Pack.verify_text(text.sub(/## END OF PACK\nsha256=[0-9a-f]{64}\n\z/, "")),
             "a missing terminal marker must fail verification"
    ensure
      Thread.current[:snapshot_repo] = nil
    end
  end

  def test_integrity_helper_rejects_a_changed_footer_digest
    sealed = Pack.seal_text("# sample pack\n")

    assert Pack.verify_text(sealed)
    wrong_digest = "sha256=" + ("0" * 64)
    refute Pack.verify_text(sealed.sub(/sha256=[0-9a-f]{64}/, wrong_digest))
    refute Pack.verify_text(sealed.delete_suffix("\n"))
  end
  def test_map_skips_magic_comments_and_truncates_summaries_at_word_boundaries
    long_purpose = Array.new(20, "completeword").join(" ")
    truncated = Map.truncate_at_word(long_purpose, Map::MAP_PURPOSE)

    assert truncated.end_with?("…")
    assert_includes truncated, "completeword"
    refute_includes truncated, "completewor…"

    original = "# frozen_string_literal: true\n# Parses a stylesheet.\nmodule Example\n  def run\n  end\nend\n"
    line = Map.map_line({ path: "lib/example.rb", original:, minified: Pack.minify("lib/example.rb", original) })

    assert_includes line, "Parses a stylesheet."
    refute_includes line, "frozen_string_literal"
  end

  def test_map_extracts_scss_mixins_placeholders_and_top_level_selectors
    source = <<~SCSS
      @mixin focus-ring { outline: 2px solid; }
      %button-reset { border: 0; }
      .card {
        color: red;
      }
      @media (max-width: 600px) {
        .nested {
          color: blue;
        }
      }
    SCSS

    summary = Map.map_declarations("application.scss", source)

    assert_includes summary, "mixins: focus-ring"
    assert_includes summary, "placeholders: %button-reset"
    assert_includes summary, "selectors: .card"
    refute_includes summary, ".nested", "nested selectors are not presented as top-level"
  end

  def test_map_extracts_erb_partials_forms_and_turbo_targets
    source = <<~ERB
      <%= render "shared/message" %>
      <%= form_with model: @message do |form| %>
        <%= turbo_frame_tag "messages" do %>
        <% end %>
      <% end %>
    ERB

    summary = Map.map_declarations("app/views/messages/_form.html.erb", source)

    assert_includes summary, "renders: shared/message"
    assert_includes summary, "forms: form_with"
    assert_includes summary, "frames: messages"
  end

  def test_map_extracts_shell_functions
    source = <<~SH
      open_browser() {
        true
      }
      function install_dependencies {
        true
      }
    SH

    assert_equal "functions: open_browser install_dependencies", Map.map_declarations("bin/setup.sh", source)
  end

  def test_unknown_stimulus_value_types_fall_back_to_generic_declarations
    source = <<~JS
      class MessageController extends Controller {
        static values = { changedAt: Date }
        connect() {
          this.element.focus()
        }
      }
    JS

    summary = Map.map_declarations("message_controller.js", source)

    assert_includes summary, "MessageController"
  end

  def test_map_exposes_stimulus_targets_values_and_methods
    source = <<~JS
      export default class extends Controller {
        static targets = ["message", "composer"]
        static values = { unread: Boolean, roomId: String }

        connect() {
          this.messageTarget.focus()
        }

        focusLastMessage() {
          this.messageTarget.focus()
        }
      }
    JS

    summary = Map.map_declarations("message_controller.js", source)

    assert_includes summary, "targets: message composer"
    assert_includes summary, "values: unread roomId"
    assert_includes summary, "methods: connect focusLastMessage"
  end
  def git!(repo, *args)
    output, status = Open3.capture2e("git", "-C", repo, *args)
    raise "git #{args.join(" ")} failed: #{output}" unless status.success?

    output
  end

  def init_snapshot_repo(repo)
    git!(repo, "init", "-q", "-b", "main")
    git!(repo, "config", "user.name", "snapshot test")
    git!(repo, "config", "user.email", "snapshot@example.invalid")
  end

  def test_since_requires_a_budget_and_refuses_mirror_or_verify_modes
    _out, err = capture_io do
      assert_equal 2, Operator::Snapshot.cli(["MASTER", "--since=HEAD"])
      assert_equal 2, Operator::Snapshot.cli(["MASTER", "--since=HEAD", "--budget=1000", "--mirror"])
      assert_equal 2, Operator::Snapshot.cli(["MASTER", "--since=HEAD", "--budget=1000", "--verify"])
      assert_equal 2, Operator::Snapshot.cli(["MASTER", "--budget=not-a-number"])
      assert_equal 2, Operator::Snapshot.cli(["MASTER", "--budget=0"])
      assert_equal 2, Operator::Snapshot.cli(["MASTER", "--part-bytes=invalid"])
      assert_equal 2, Operator::Snapshot.cli(["MASTER", "--only="])
      assert_equal 2, Operator::Snapshot.cli(["MASTER", "--since="])
    end

    assert_includes err, "--since requires --budget=BYTES"
    assert_includes err, "--since cannot be combined with --mirror or --verify"
    assert_includes err, "--budget must be a positive integer"
    assert_includes err, "--part-bytes must be a positive integer"
    assert_includes err, "--only needs at least one non-empty path"
    assert_includes err, "--since needs a non-empty commit reference"
  end
  def test_incremental_pack_keeps_the_full_map_but_inlines_only_changed_tracked_source
    Dir.mktmpdir("snapshot-since-") do |repo|
      Thread.current[:snapshot_repo] = repo
      FileUtils.mkdir_p(File.join(repo, "DEMO/lib"))
      File.write(File.join(repo, "DEMO/lib/changed.rb"), "value = :before\n")
      File.write(File.join(repo, "DEMO/lib/unchanged.rb"), "value = :unchanged\n")
      init_snapshot_repo(repo)
      git!(repo, "add", "DEMO")
      git!(repo, "commit", "-q", "-m", "baseline")
      File.write(File.join(repo, "DEMO/lib/changed.rb"), "value = :after\n")

      Pack.write(Host, "DEMO", budget: 20_000, since: "HEAD", io: StringIO.new)
      text = File.read(File.join(repo, "snapshot_DEMO.md"))

      assert Pack.verify_text(text), "incremental packs retain the pack integrity marker"
      assert_includes text, "## Changes since \"HEAD\""
      assert_includes text, "changed=1"
      assert_includes text, "changed.rb [1L] Δ"
      assert_includes text, "value = :after"
      refute_includes text, "value = :unchanged", "unchanged source must remain map-only"
      assert_includes text, "unchanged.rb [1L]"
      assert_raises(ArgumentError) { Pack.write(Host, "DEMO", budget: 20_000, since: "not-a-real-ref", io: StringIO.new) }
      assert_equal text, File.read(File.join(repo, "snapshot_DEMO.md")), "an invalid base must not destroy the prior pack"
    ensure
      Thread.current[:snapshot_repo] = nil
    end
  end

  def test_incremental_change_set_reports_deletions_and_renames_and_rejects_unknown_refs
    Dir.mktmpdir("snapshot-diff-") do |repo|
      Thread.current[:snapshot_repo] = repo
      FileUtils.mkdir_p(File.join(repo, "DEMO/lib"))
      File.write(File.join(repo, "DEMO/lib/old.rb"), "value = :move_me\n")
      File.write(File.join(repo, "DEMO/lib/gone.rb"), "value = :gone\n")
      File.write(File.join(repo, "DEMO/lib/edit.rb"), "value = :before\n")
      init_snapshot_repo(repo)
      git!(repo, "add", "DEMO")
      git!(repo, "commit", "-q", "-m", "baseline")
      File.rename(File.join(repo, "DEMO/lib/old.rb"), File.join(repo, "DEMO/lib/new.rb"))
      File.delete(File.join(repo, "DEMO/lib/gone.rb"))
      File.write(File.join(repo, "DEMO/lib/edit.rb"), "value = :after\n")
      git!(repo, "add", "-A")

      changes = Pack.change_set(Host, "DEMO", "HEAD")

      assert_includes changes[:current], "DEMO/lib/new.rb"
      assert_includes changes[:current], "DEMO/lib/edit.rb"
      assert_includes changes[:deleted], "DEMO/lib/gone.rb"
      assert_includes changes[:renamed], ["DEMO/lib/old.rb", "DEMO/lib/new.rb"]
      scoped = Pack.change_set(Host, "DEMO", "HEAD", only: "lib/edit.rb")
      assert_equal ["DEMO/lib/edit.rb"], scoped[:current]
      assert_empty scoped[:deleted]
      assert_empty scoped[:renamed]
      assert_raises(ArgumentError) { Pack.change_set(Host, "DEMO", "no-such-snapshot-ref") }
    ensure
      Thread.current[:snapshot_repo] = nil
    end
  end
  def test_budget_is_hard_and_failed_build_preserves_the_last_good_pack
    Dir.mktmpdir("snapshot-budget-") do |repo|
      Thread.current[:snapshot_repo] = repo
      FileUtils.mkdir_p(File.join(repo, "DEMO/lib"))
      File.write(File.join(repo, "DEMO/lib/example.rb"), "value = :stable\n")

      Pack.write(Host, "DEMO", budget: 20_000, io: StringIO.new)
      path = File.join(repo, "snapshot_DEMO.md")
      previous = File.binread(path)
      assert_operator previous.bytesize, :<=, 20_000

      assert_raises(ArgumentError) do
        Pack.write(Host, "DEMO", budget: 50, io: StringIO.new)
      end
      assert_equal previous, File.binread(path), "an impossible budget must not erase the previous valid pack"

      35.times do |index|
        File.write(File.join(repo, "DEMO/lib", "changed_#{index}.rb"), "value = #{index}\n")
      end
      Pack.write(Host, "DEMO", budget: 4_000, io: StringIO.new)
      regenerated = File.binread(path)
      assert_operator regenerated.bytesize, :<=, 4_000, "the final source blocks must fit the budget"
      assert Pack.verify_text(regenerated)
    ensure
      Thread.current[:snapshot_repo] = nil
    end
  end
    # A host standing in for tools/snapshot.rb: a repo root, its tracked files, the same predicates.
  class Host
    TREE_PATHS = { "DEMO" => "DEMO" }.freeze

    class << self
      def const_missing(name) = name == :REPO ? Thread.current[:snapshot_repo] : super

      def tracked(_tree)
        repo = Thread.current[:snapshot_repo]
        Dir.glob("DEMO/**/*", base: repo).select { |p| File.file?(File.join(repo, p)) }.sort
      end

      def all_tracked(_tree)
        repo = Thread.current[:snapshot_repo]
        Dir.glob("DEMO/**/*", File::FNM_DOTMATCH, base: repo).select { |p| File.file?(File.join(repo, p)) }.sort
      end

      def binary?(_path) = false
      def head_sha = "abc1234"
    end
  end

  def test_regenerating_deletes_every_old_snapshot_file_of_the_tree_first
    Dir.mktmpdir do |repo|
      Thread.current[:snapshot_repo] = repo
      FileUtils.mkdir_p(File.join(repo, "DEMO/lib"))
      File.write(File.join(repo, "DEMO/lib/a.rb"), "# Does a.\nputs 1\n")
      stale = %w[snapshot_DEMO.md snapshot_DEMO.part002.md snapshot_OTHER.md notes.md]
      stale.each { |name| File.write(File.join(repo, name), "old") }

      Pack.write(Host, "DEMO", io: StringIO.new)

      names = Dir.children(repo)
      assert_equal %w[snapshot_DEMO.md], names.grep(/\Asnapshot_DEMO/), "one file a tree, and none of the old ones\n"
      assert_includes names, "snapshot_OTHER.md", "another tree's snapshot is not this tree's to delete"
      assert_includes names, "notes.md"
      assert_includes File.read(File.join(repo, "snapshot_DEMO.md")), "puts 1"
      assert_includes File.read(File.join(repo, "snapshot_DEMO.md")), "# Does a.\nputs 1", "the first comment stays as the purpose line"
    ensure
      Thread.current[:snapshot_repo] = nil
    end
  end

  # A dotfile is source (.rubocop.yml, .ruby-version, .gitignore); only tool state and generated
  # directories are left out, and the Omitted line names them.
  def test_full_mode_keeps_dotfiles_and_names_what_it_leaves_out
    Dir.mktmpdir do |repo|
      Thread.current[:snapshot_repo] = repo
      %w[DEMO/lib DEMO/.master DEMO/storage].each { |dir| FileUtils.mkdir_p(File.join(repo, dir)) }
      File.write(File.join(repo, "DEMO/.rubocop.yml"), "AllCops:\n  NewCops: enable\n")
      File.write(File.join(repo, "DEMO/lib/a.rb"), "puts 1\n")
      File.write(File.join(repo, "DEMO/.master/state.json"), "{}\n")
      File.write(File.join(repo, "DEMO/storage/blob.txt"), "x\n")

      Pack.write(Host, "DEMO", io: StringIO.new, full: true)
      text = File.read(File.join(repo, "snapshot_DEMO.md"))

      assert_includes text, "### DEMO/.rubocop.yml"
      refute_includes text, "### DEMO/.master/state.json"
      refute_includes text, "### DEMO/storage/blob.txt"
      assert_includes text, "tool state (1)"
      assert_includes text, "generated or dependency directory (1)"
    ensure
      Thread.current[:snapshot_repo] = nil
    end
  end

  # tools/snapshot.rb reads 8000 bytes to decide text or binary; a multibyte character cut at
  # that boundary made four real source files look binary and dropped them from every pack.
  def test_a_multibyte_character_cut_at_the_read_boundary_is_not_binary
    require_relative "../tools/snapshot"
    Dir.mktmpdir do |dir|
      cut = File.join(dir, "cut.yml")
      File.write(cut, ("a" * 7999) + "é" + ("b" * 50), encoding: "UTF-8")
      real = File.join(dir, "real.bin")
      File.binwrite(real, ("a" * 100) + "\xFF\xFE".b + ("b" * 9000))

      refute Operator::Snapshot.binary?(cut), "a character split by the 8000-byte read is text"
      assert Operator::Snapshot.binary?(real), "invalid bytes inside the read are binary"
    end
  end

  # /snapshot writes the full source: comments, tests and files over FILE_CAP all come in whole.
  def test_full_mode_inlines_every_text_file_byte_for_byte
    Dir.mktmpdir do |repo|
      Thread.current[:snapshot_repo] = repo
      FileUtils.mkdir_p(File.join(repo, "DEMO/lib"))
      FileUtils.mkdir_p(File.join(repo, "DEMO/test"))
      source = "# Does a.\n# A second comment.\n\nputs 1\n"
      big = "x = 1\n" * (Pack::FILE_CAP / 6 + 10)
      File.write(File.join(repo, "DEMO/lib/a.rb"), source)
      File.write(File.join(repo, "DEMO/lib/big.rb"), big)
      File.write(File.join(repo, "DEMO/test/a_test.rb"), "# a test\nassert true\n")
      File.write(File.join(repo, "DEMO/Gemfile.lock"), "locked\n")

      Pack.write(Host, "DEMO", io: StringIO.new, full: true)
      text = File.read(File.join(repo, "snapshot_DEMO.md"))

      assert_includes text, source, "comments and blank lines stay"
      assert_includes text, big, "a file over FILE_CAP is inlined whole"
      assert_includes text, "# a test\nassert true", "tests are source"
      refute_includes text, "locked", "a lockfile is still left out, and named"
      assert_includes text, "budget=full"
      assert_includes text, "lockfile (1)"
    ensure
      Thread.current[:snapshot_repo] = nil
    end
  end
end
