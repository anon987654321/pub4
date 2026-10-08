# frozen_string_literal: true

require_relative "test_helper"

# CommitGuard's omission detector, untested.
#
# It answers one question -- "did this edit delete a public name" -- and it
# answers it by diffing two signature sets. Every way it can be wrong is a way
# an agent silently deletes an API and the guard says nothing: a namespace it
# fails to walk into, a `def self.x` it records under the instance name, a parse
# failure it swallows into an empty set that then looks like a file with no API
# at all.
#
# That last one is the dangerous shape. from_source rescues and returns [], and
# an empty *new* set makes every old name look deleted while an empty *old* set
# makes nothing look deleted. The direction matters and nothing pinned it.
class TestAstSignature < Minitest::Test
  A = Master::Review::AstSignature

  def sigs(source) = A.from_source(source)

  def names(source, type) = sigs(source).select { |s| s.type == type }.map(&:name)

  # --- what it records ----------------------------------------------------

  def test_a_bare_method_is_recorded_by_name
    assert_equal ["greet"], names("def greet; end", :method)
  end

  def test_a_method_is_namespaced_by_its_enclosing_class
    assert_equal ["A::B#greet"], names("module A; class B; def greet; end; end; end", :method)
  end

  # `.` and `#` are not decoration: Foo.bar and Foo#bar are different API and a
  # guard that conflates them misses the deletion of one of them.
  def test_a_singleton_method_is_recorded_with_a_dot
    assert_equal ["A.build"], names("class A; def self.build; end; end", :method)
  end

  def test_an_instance_and_a_singleton_of_one_name_are_two_signatures
    found = names("class A; def run; end; def self.run; end; end", :method)

    assert_equal %w[A#run A.run].sort, found.sort
  end

  def test_classes_and_modules_are_recorded_fully_qualified
    source = "module A; module B; class C; end; end; end"

    assert_equal ["A", "A::B"], names(source, :module)
    assert_equal ["A::B::C"], names(source, :class)
  end

  def test_a_constant_is_recorded
    assert_includes names("module A; LIMIT = 5; end", :constant), "A::LIMIT"
  end

  def test_a_compact_constant_path_assignment_is_recorded_as_written
    assert_includes names("A::B::LIMIT = 5", :constant), "A::B::LIMIT"
  end

  def test_an_endless_method_is_recorded
    assert_equal ["A#double"], names("class A; def double(x) = x * 2; end", :method)
  end

  def test_every_signature_carries_the_line_it_was_found_on
    found = sigs("class A\n  def one; end\n\n  def two; end\nend\n")
    two = found.find { |s| s.name == "A#two" }

    assert_equal 4, two.line
    found.each { |sig| assert_operator sig.line, :>, 0 }
  end

  def test_a_namespace_closes_after_its_body
    source = "module A; def inside; end; end\ndef outside; end\n"
    found = names(source, :method)

    assert_includes found, "A#inside"
    assert_includes found, "outside", "the namespace stack was never popped"
  end

  # --- parse failure ------------------------------------------------------

  # The direction that matters. A file that no longer parses yields no
  # signatures, so `diff(old, new)` reports every name in the file as deleted --
  # which is exactly right, because from the guard's point of view they are.
  def test_a_file_that_stopped_parsing_yields_nothing
    assert_empty sigs("def broken(")
  end

  def test_a_broken_edit_reads_as_deleting_everything_it_had
    old = sigs("class A; def one; end; def two; end; end")
    new = sigs("class A; def one; end; def two(")

    deleted = A.diff(old, new).map(&:name)
    assert_includes deleted, "A#one"
    assert_includes deleted, "A#two"
  end

  def test_an_empty_file_has_no_api
    assert_empty sigs("")
    assert_empty sigs("# just a comment\n")
  end

  # --- the diff -----------------------------------------------------------

  def test_a_deleted_method_is_reported
    old = sigs("class A; def one; end; def two; end; end")
    new = sigs("class A; def one; end; end")

    assert_equal ["A#two"], A.diff(old, new).map(&:name)
  end

  def test_an_added_method_is_not_a_deletion
    old = sigs("class A; def one; end; end")
    new = sigs("class A; def one; end; def two; end; end")

    assert_empty A.diff(old, new)
  end

  def test_a_moved_method_keeps_its_name_and_is_not_reported
    old = sigs("class A; def one; end; end")
    new = sigs("class A\n\n\n  def one; end\nend")

    assert_empty A.diff(old, new), "a line number change read as a deletion"
  end

  # A method moved between namespaces IS a deletion of the old name: callers of
  # A#one break. The guard must not treat the basename as identity.
  def test_a_method_moved_to_another_namespace_is_a_deletion
    old = sigs("class A; def one; end; end")
    new = sigs("class B; def one; end; end")

    # Class A goes with it: renaming the class deletes both names, and a
    # caller of either breaks.
    assert_equal ["A", "A#one"], A.diff(old, new).map(&:name).sort
  end

  def test_an_instance_method_becoming_a_class_method_is_a_deletion
    old = sigs("class A; def one; end; end")
    new = sigs("class A; def self.one; end; end")

    assert_equal ["A#one"], A.diff(old, new).map(&:name)
  end

  # Constants are excluded by default and that is deliberate: a constant moving
  # or being computed differently is not the omission this guard is for. It has
  # to be opt-in rather than silently unreachable.
  def test_constants_are_excluded_by_default_and_reachable_on_request
    old = sigs("class A; LIMIT = 1; end")
    new = sigs("class A; end")

    assert_empty A.diff(old, new)
    assert_equal ["A::LIMIT"], A.diff(old, new, kinds: %i[constant]).map(&:name)
  end

  def test_a_deleted_class_is_reported
    old = sigs("class A; end\nclass B; end")
    new = sigs("class A; end")

    assert_equal ["B"], A.diff(old, new).map(&:name)
  end

  def test_diffing_a_file_against_itself_reports_nothing
    found = sigs("module A; class B; def one; end; C = 1; end; end")

    assert_empty A.diff(found, found)
    assert_empty A.diff(found, found, kinds: %i[method class module constant])
  end

  def test_the_diff_returns_signatures_rather_than_bare_names
    old = sigs("class A; def one; end; end")
    deleted = A.diff(old, []).find { |sig| sig.type == :method }

    assert_equal :method, deleted.type
    assert_equal "A#one", deleted.name
    assert_operator deleted.line, :>, 0
  end
end
