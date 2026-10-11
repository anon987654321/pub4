# frozen_string_literal: true

require_relative "test_helper"

class TestCodeIndexStore < Minitest::Test
  Index = Master::Review::CodeIndex

  def with_tree
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      File.write(File.join(root, "a.rb"), "class Alpha\n  def one = 1\nend\n")
      File.write(File.join(root, "b.rb"), "class Beta\n  def two = Alpha.new.one\nend\n")
      yield root
    end
  end

  # Counts the files Prism parses, which is the cost the snapshot exists to skip.
  def parsed_files
    parsed = []
    original = Prism.method(:parse)
    Prism.define_singleton_method(:parse) { |src, *rest| parsed << src[/class (\w+)/, 1] and original.call(src, *rest) }
    yield parsed
  ensure
    Prism.define_singleton_method(:parse, original)
  end

  def test_warm_boot_parses_nothing_and_answers_the_same
    with_tree do |root|
      cold = Index.new(root:, persist: true).build
      parsed_files do |parsed|
        warm = Index.new(root:, persist: true).build

        assert_empty parsed
        assert_equal cold.size, warm.size
        assert_equal cold.lookup("Alpha#one"), warm.lookup("Alpha#one")
        assert_equal cold.impact("Alpha#one")[:reference_count], warm.impact("Alpha#one")[:reference_count]
      end
    end
  end

  def test_only_the_changed_file_is_reparsed_and_its_old_symbols_go
    with_tree do |root|
      Index.new(root:, persist: true).build
      File.write(File.join(root, "a.rb"), "class Alpha\n  def renamed_method = 1\n  def extra = 2\nend\n")
      parsed_files do |parsed|
        warm = Index.new(root:, persist: true).build

        assert_equal ["Alpha"], parsed
        assert warm.lookup("Alpha#renamed_method")
        assert_nil warm.lookup("Alpha#one")
      end
    end
  end

  def test_deleted_file_is_purged_from_the_snapshot
    with_tree do |root|
      Index.new(root:, persist: true).build
      File.delete(File.join(root, "b.rb"))

      assert_nil Index.new(root:, persist: true).build.lookup("Beta#two")
    end
  end

  def test_a_snapshot_from_other_parsing_logic_is_rejected
    with_tree do |root|
      Index.new(root:, persist: true).build
      store = Master::Review::CodeIndexStore.new(root:)
      data = JSON.parse(File.read(store.path))
      data["stamp"] = [0, "old", "old"]
      File.write(store.path, JSON.generate(data))

      parsed_files do |parsed|
        Index.new(root:, persist: true).build
        assert_equal %w[Alpha Beta], parsed.sort
      end
    end
  end

  def test_without_persist_nothing_is_written
    with_tree do |root|
      Index.new(root:).build

      refute File.exist?(File.join(root, ".master"))
    end
  end

  def test_a_corrupt_snapshot_falls_back_to_a_full_build
    with_tree do |root|
      Index.new(root:, persist: true).build
      File.write(Master::Review::CodeIndexStore.new(root:).path, "{not json")

      assert Index.new(root:, persist: true).build.lookup("Beta#two")
    end
  end
end

class TestCodeIndexSummaryMemo < Minitest::Test
  def test_summary_orientation_is_stable_then_follows_a_reindex
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      File.write(File.join(root, "a.rb"), "class Alpha\nend\n")
      index = Master::Review::CodeIndex.new(root:).build

      assert_equal index.summary, index.summary
      before = index.summary
      File.write(File.join(root, "b.rb"), "class Beta\nend\n")
      index.reindex(File.join(root, "b.rb"))

      refute_equal before, index.summary
      assert_includes index.summary, "2 symbols"
    end
  end
end
