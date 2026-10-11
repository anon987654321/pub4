# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require "minitest/mock"
require_relative "../tools/snapshot"

# The full source is written as parts small enough to upload, split only at safe boundaries,
# written exact and code-only, and proved against the tree after it is written.
class TestSnapshotParts < Minitest::Test
  Split = Operator::SnapshotSplit
  Parts = Operator::SnapshotParts
  Verify = Operator::SnapshotVerify

  class Host
    TREE_PATHS = { "DEMO" => "DEMO" }.freeze

    class << self
      def const_missing(name) = name == :REPO ? Thread.current[:parts_repo] : super

      def all_tracked(_tree)
        repo = Thread.current[:parts_repo]
        Dir.glob("DEMO/**/*", File::FNM_DOTMATCH, base: repo).select { |p| File.file?(File.join(repo, p)) }.sort
      end

      def binary?(_path) = false
      def head_sha = "abc1234"
    end
  end

  def with_repo
    Dir.mktmpdir do |repo|
      Thread.current[:parts_repo] = repo
      FileUtils.mkdir_p(File.join(repo, "DEMO/lib"))
      yield repo
    ensure
      Thread.current[:parts_repo] = nil
    end
  end

  def put(repo, path, text) = File.write(File.join(repo, path), text)

  def methods_class(count)
    body = (1..count).map { |i| "  # Number #{i}.\n  def m#{i}\n    #{i}\n  end\n" }.join("\n")
    "# Demo.\nclass Big\n#{body}end\n"
  end

  # --- splitting ---

  def test_a_ruby_file_is_cut_between_methods_and_rejoins_byte_for_byte
    source = methods_class(40)
    chunks = Split.chunks("big.rb", source, 400)

    assert_operator chunks.size, :>, 2
    assert_equal source, chunks.join
    chunks.drop(1).each { |chunk| assert_match(/\A  # Number \d+\.\n  def m\d+/, chunk, "a chunk starts at a method with its comment") }
    assert(chunks.all? { |c| c.bytesize <= 800 }, "no chunk beyond twice the limit")
  end

  def test_a_heredoc_body_that_looks_like_a_statement_is_never_a_cut
    text = "x = <<~T\n#{"def fake\nend\n" * 30}T\n#{(1..30).map { |i| "y#{i} = #{i}\n" }.join}"
    chunks = Split.chunks("h.rb", text, 200)

    assert_equal text, chunks.join
    chunks.drop(1).each { |chunk| refute chunk.start_with?("def fake"), "cut inside a heredoc" }
  end

  def test_stylesheets_are_cut_between_top_level_rules_not_inside_one
    css = (1..60).map { |i| ".a#{i},\n.b#{i} {\n  color: red;\n  margin: 0;\n}\n" }.join
    chunks = Split.chunks("x.scss", css, 300)

    assert_equal css, chunks.join
    assert_operator chunks.size, :>, 3
    chunks.drop(1).each { |chunk| assert_match(/\A\.a\d+,\n\.b\d+ \{/, chunk) }
  end

  def test_other_text_is_cut_at_a_column_zero_line_after_a_blank_line
    yaml = (1..50).map { |i| "key#{i}:\n  - a\n  - b\n" }.join("\n")
    chunks = Split.chunks("x.yml", yaml, 200)

    assert_equal yaml, chunks.join
    chunks.drop(1).each { |chunk| assert_match(/\Akey\d+:\n/, chunk) }
  end

  def test_with_no_safe_boundary_the_cut_falls_on_a_line_and_never_inside_one
    text = (1..200).map { |i| "  indented line #{i}\n" }.join
    chunks = Split.chunks("flat.txt", text, 500)

    assert_equal text, chunks.join
    assert_operator chunks.size, :>, 5
    assert(chunks.all? { |c| c.end_with?("\n") }, "every cut is at a line end")
  end

  # --- parts ---

  def test_a_tree_is_written_as_numbered_parts_each_carrying_the_same_header_and_the_whole_map
    with_repo do |repo|
      6.times { |i| put(repo, "DEMO/lib/f#{i}.rb", "# File #{i}.\n#{"puts #{i}\n" * 800}") }
      Operator::SnapshotPack.write(Host, "DEMO", io: StringIO.new, full: true, part_bytes: 12_000)

      names = Dir.children(repo).grep(/\Asnapshot_DEMO/).sort
      count = names.size
      assert_operator count, :>, 2
      assert_equal (1..count).map { |k| format("snapshot_DEMO.part%02d-of-%02d.md", k, count) }, names
      texts = names.map { |n| File.read(File.join(repo, n)) }
      maps = texts.map { |t| t[/## Map\n.*?\n## Source/m] }
      assert_equal 1, maps.uniq.size, "every part holds the same complete Map"
      assert_includes maps.first, "f5.rb [801L] p0"
      assert(texts.each_with_index.all? { |t, i| t.include?("part=#{i + 1}/#{count}") && t.include?("git=abc1234") })
      assert(texts.all? { |t| t.bytesize <= 12_000 }, "a part stays within the size")
      assert_includes texts.first, "Reading guide:"
    end
  end

  def test_a_tree_that_fits_one_part_keeps_the_plain_file_name
    with_repo do |repo|
      put(repo, "DEMO/lib/a.rb", "puts 1\n")
      Operator::SnapshotPack.write(Host, "DEMO", io: StringIO.new, full: true)

      assert_equal ["snapshot_DEMO.md"], Dir.children(repo).grep(/snapshot/)
    end
  end

  def test_a_file_bigger_than_a_part_is_split_into_labelled_blocks_that_rejoin
    with_repo do |repo|
      source = methods_class(200)
      put(repo, "DEMO/lib/big.rb", source)
      put(repo, "DEMO/lib/small.rb", "puts 1\n")
      Operator::SnapshotPack.write(Host, "DEMO", io: StringIO.new, full: true, part_bytes: 6_000)

      text = Dir.children(repo).grep(/snapshot_DEMO/).sort.map { |n| File.read(File.join(repo, n)) }.join
      assert_match(/^### DEMO\/lib\/big\.rb \(part 1 of \d+, lines 1-\d+\)$/, text)
      assert_includes text, "[continued in the next block]"
      assert_includes text, "[continues from the previous block]"
      assert_equal 2, Verify.call(Host, "DEMO", variant: :exact, io: StringIO.new)
    end
  end

  def test_a_file_without_a_trailing_newline_and_a_file_with_backtick_fences_survive_exactly
    with_repo do |repo|
      put(repo, "DEMO/lib/bare.txt", "no newline at the end")
      put(repo, "DEMO/lib/doc.md", "# T\n\n````\n```ruby\nx\n```\n````\n")
      put(repo, "DEMO/lib/empty.txt", "")
      Operator::SnapshotPack.write(Host, "DEMO", io: StringIO.new, full: true)

      assert_equal 3, Verify.call(Host, "DEMO", variant: :exact, io: StringIO.new)
    end
  end

  def test_the_code_variant_drops_comments_and_is_named_with_code
    with_repo do |repo|
      put(repo, "DEMO/lib/a.rb", "# Does a.\n# Second.\n\nputs 1 # trailing\n")
      Operator::SnapshotPack.write(Host, "DEMO", io: StringIO.new, full: true, variants: %i[exact code])

      assert_equal %w[snapshot_DEMO.code.md snapshot_DEMO.md], Dir.children(repo).grep(/snapshot/).sort
      code = File.read(File.join(repo, "snapshot_DEMO.code.md"))
      assert_includes code, "# Does a.\nputs 1"
      refute_includes code, "Second."
      refute_includes code, "trailing"
      assert_includes File.read(File.join(repo, "snapshot_DEMO.md")), "# Second."
    end
  end

  def test_regenerating_deletes_every_old_variant_and_part_of_the_tree_only
    with_repo do |repo|
      put(repo, "DEMO/lib/a.rb", "puts 1\n")
      old = %w[snapshot_DEMO.md snapshot_DEMO.code.md snapshot_DEMO.part02-of-03.md snapshot_DEMO.code.part01-of-02.md snapshot_DEMO.part003.md]
      (old + %w[snapshot_OTHER.md snapshot_DEMOS.md notes.md]).each { |n| put(repo, n, "old") }

      Operator::SnapshotPack.write(Host, "DEMO", io: StringIO.new, full: true)

      assert_equal %w[snapshot_DEMO.md snapshot_DEMOS.md snapshot_OTHER.md], Dir.children(repo).grep(/snapshot/).sort
      assert_includes Dir.children(repo), "notes.md"
    end
  end

  def test_the_part_size_can_come_from_the_environment
    with_repo do |repo|
      4.times { |i| put(repo, "DEMO/lib/f#{i}.rb", "#{"puts #{i}\n" * 800}") }
      ENV["MASTER_SNAPSHOT_PART_BYTES"] = "9000"
      Operator::SnapshotPack.write(Host, "DEMO", io: StringIO.new, full: true)

      assert_operator Dir.children(repo).grep(/part\d+-of-\d+/).size, :>, 1
    ensure
      ENV.delete("MASTER_SNAPSHOT_PART_BYTES")
    end
  end

  # --- verification ---

  def written(repo, **options)
    put(repo, "DEMO/lib/a.rb", "# A.\nputs 1\n")
    put(repo, "DEMO/lib/b.rb", "# B.\nputs 2\n")
    Operator::SnapshotPack.write(Host, "DEMO", io: StringIO.new, full: true, **options)
  end

  def test_verify_reports_the_file_count_and_zero_missing
    with_repo do |repo|
      written(repo)
      out = StringIO.new
      Verify.call(Host, "DEMO", variant: :exact, io: out)

      assert_match(/snapshot0: DEMO verified 2 files, 0 missing/, out.string)
    end
  end

  def test_verify_fails_loudly_on_a_file_the_pack_lacks
    with_repo do |repo|
      written(repo)
      put(repo, "DEMO/lib/c.rb", "puts 3\n")

      error = assert_raises(Verify::Failed) { Verify.call(Host, "DEMO", variant: :exact, io: StringIO.new) }
      assert_match(/missing: DEMO\/lib\/c\.rb/, error.message)
    end
  end

  def test_verify_fails_on_one_changed_byte
    with_repo do |repo|
      written(repo)
      path = File.join(repo, "snapshot_DEMO.md")
      File.write(path, File.read(path).sub("puts 2", "puts 9"))

      error = assert_raises(Verify::Failed) { Verify.call(Host, "DEMO", variant: :exact, io: StringIO.new) }
      assert_match(/DEMO\/lib\/b\.rb: differs at byte/, error.message)
    end
  end

  def test_verify_fails_when_a_part_is_absent_or_a_block_is_dropped
    with_repo do |repo|
      put(repo, "DEMO/lib/pad.rb", "puts 0\n" * 600)
      written(repo, part_bytes: 4_500)
      parts = Dir.children(repo).grep(/part/).sort
      assert_operator parts.size, :>, 1
      FileUtils.rm(File.join(repo, parts.last))

      error = assert_raises(Verify::Failed) { Verify.call(Host, "DEMO", variant: :exact, io: StringIO.new) }
      assert_match(/expects \d+ parts, found/, error.message)
    end
  end

  def test_verify_checks_ruby_tokens_in_the_code_variant
    with_repo do |repo|
      written(repo, variants: [:code])
      path = File.join(repo, "snapshot_DEMO.code.md")
      File.write(path, File.read(path).sub("puts 1", "puts 7"))

      error = assert_raises(Verify::Failed) { Verify.call(Host, "DEMO", variant: :code, io: StringIO.new) }
      assert_match(/DEMO\/lib\/a\.rb/, error.message)
    end
  end

  def test_a_write_verifies_itself_and_a_dropped_file_cannot_pass
    with_repo do |repo|
      written(repo)
      Operator::SnapshotParts.stub(:collect, ->(*) { [[], Hash.new { |h, k| h[k] = [] }] }) do
        assert_raises(Verify::Failed) do
          Operator::SnapshotPack.write(Host, "DEMO", io: StringIO.new, full: true)
        end
      end
    end
  end

  # --- command line ---

  def test_the_command_line_rejects_what_it_does_not_know
    out, err = capture_io { assert_equal 2, Operator::Snapshot.cli(["--exact-only"]) }

    assert_empty out
    assert_includes err, "unknown option --exact-only"
    assert_includes err, "--part-bytes=N"
  end

  def test_the_dispatcher_writes_exact_parts_and_reports_a_line_a_file
    source = File.read(File.expand_path("../lib/cli/command_registry.rb", __dir__))
    assert_includes source, "Operator::Snapshot.write(tree, full: true, io: log)"
    assert_includes source, "snapshot0: wrote root/"
    assert_includes source, "~\#{bytes / 4000}K tokens"
  end

  def test_the_usage_text_names_every_snapshot_flag
    usage = File.read(File.expand_path("../bin/operator", __dir__))[/bin\/operator snapshot [^\n]*/]
    %w[--part-bytes --code --verify].each { |flag| assert_includes usage, flag }
  end
end
