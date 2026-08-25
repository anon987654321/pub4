# frozen_string_literal: true

require_relative "test_helper"
require "pub4/readers"
require "tmpdir"
require "fileutils"

# Pub4::Readers exists because "its only reader is X" has been wrong four times
# in this repo, and each time the grep behind that sentence could not see the
# one reference that mattered. So the cases here are those four, reproduced as
# fixtures rather than described — a tool built to stop a specific mistake has
# to be shown failing to catch it first.
class TestReaders < Minitest::Test
  def with_tree
    Dir.mktmpdir do |root|
      %w[MASTER RAILS STUDIO OPENBSD].each { |t| FileUtils.mkdir_p(File.join(root, t)) }
      yield root
    end
  end

  def write(root, rel, body)
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  def find(root, target) = Pub4::Readers.find(root: root, target: target)

  def hard(hits) = hits.reject { |h| h.kind == :mention }

  # The expensive one. The reader was in a different tree, built the path with
  # File.expand_path, left the extension off, and sat inside a rescue LoadError
  # so the breakage warned instead of raising.
  def test_a_path_built_require_from_another_tree_is_found
    with_tree do |root|
      write(root, "MASTER/lib/boot/hash_dig_compat.rb", "module Master; end\n")
      write(root, "STUDIO/dilla/lib/music_gems.rb", <<~RUBY)
        def bootstrap!
          require File.expand_path("../../../MASTER/lib/boot/hash_dig_compat", __dir__)
        rescue LoadError
          warn "unavailable"
        end
      RUBY

      hits = find(root, "MASTER/lib/boot/hash_dig_compat.rb")

      assert_includes hits.map(&:path), "STUDIO/dilla/lib/music_gems.rb",
                      "a cross-tree require built with File.expand_path is the exact reference " \
                      "that was missed; if this is empty the tool cannot do its job"
      refute_empty hard(hits), "that reference would break on delete and must not read as a mention"
    end
  end

  # A grep for the filename finds nothing: partials are declared with a leading
  # underscore and every extension, and rendered with neither.
  def test_a_partial_rendered_by_name_is_found
    with_tree do |root|
      write(root, "RAILS/shared/app/views/shared/_search_loading.html.erb", "<div></div>\n")
      write(root, "RAILS/brgen/app/views/posts/index.html.erb", %(<%= render "shared/search_loading" %>\n))

      hits = find(root, "RAILS/shared/app/views/shared/_search_loading.html.erb")

      assert_includes hits.map(&:kind), :render
      assert_includes hits.map(&:path), "RAILS/brgen/app/views/posts/index.html.erb"
    end
  end

  # Nothing in the app renders it; a contract test asserts it exists. Deleting
  # it still breaks the build, so this cannot report zero.
  def test_a_file_only_a_test_asserts_is_not_unreferenced
    with_tree do |root|
      write(root, "RAILS/shared/app/views/shared/_orphan.html.erb", "<div></div>\n")
      write(root, "RAILS/test/deploy_gates_contract_test.rb", <<~RUBY)
        %w[_orphan.html.erb].each { |partial| assert File.exist?(partial) }
      RUBY

      hits = find(root, "RAILS/shared/app/views/shared/_orphan.html.erb")

      assert_includes hits.map(&:kind), :test,
                      "a test naming the file is the tripwire that fires on delete"
      refute_empty hard(hits)
    end
  end

  # Zeitwerk: the file is reached by a constant with no textual reference to its
  # path anywhere.
  def test_a_constant_reference_with_no_path_mention_is_found
    with_tree do |root|
      write(root, "MASTER/lib/ground/policy/sandbox.rb", "module Ground; module Policy; class Sandbox; end; end; end\n")
      write(root, "MASTER/lib/io/shell.rb", "verdict = Ground::Policy::Sandbox.decide(command)\n")

      hits = find(root, "MASTER/lib/ground/policy/sandbox.rb")

      assert_includes hits.map(&:kind), :constant
      assert_includes hits.map(&:path), "MASTER/lib/io/shell.rb"
    end
  end

  # The only case where a reader count settles anything. If this reports hits
  # the tool is noise and nobody will run it twice.
  def test_a_genuinely_unreferenced_file_reports_nothing
    with_tree do |root|
      write(root, "MASTER/lib/ground/nobody_calls_this.rb", "module Nobody; end\n")
      write(root, "MASTER/lib/io/shell.rb", "puts 'unrelated'\n")

      assert_empty find(root, "MASTER/lib/ground/nobody_calls_this.rb")
    end
  end

  # The file's own definition is not one of its callers — the mistake two
  # orphan-scanners made in the same week, which made every private helper read
  # as dead.
  def test_the_file_does_not_count_as_its_own_reader
    with_tree do |root|
      write(root, "MASTER/lib/ground/taint.rb", "module Taint\n  def taint = :taint\nend\n")

      assert_empty find(root, "MASTER/lib/ground/taint.rb")
    end
  end
end
