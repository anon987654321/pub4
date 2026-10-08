# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/method_graph"

# The census deletes what it reports, so each of its blind spots is a deletion
# of live behaviour. These are the ones its comments name, driven directly.
class TestMethodGraph < Minitest::Test
  Graph = Operator::MethodGraph

  def test_a_name_inside_an_interpolation_is_code
    assert_includes Graph.names_in(Graph.code_only(%(log "worker \#{role_description} started"))), "role_description"
  end

  def test_prose_in_a_string_and_a_trailing_comment_are_not_calls
    names = Graph.names_in(Graph.code_only(%(warn "please delete_everything now" # purge_all later)))

    refute_includes names, "delete_everything"
    refute_includes names, "purge_all"
  end

  def test_a_short_lowercase_literal_survives_because_symbol_tables_name_handlers_so
    assert_includes Graph.names_in(Graph.code_only(%(HANDLERS = { "x" => "run_rebuild" }))), "run_rebuild"
  end

  def test_a_whole_line_comment_names_nothing
    assert_empty Graph.names_in(Graph.code_only("  # dispatch_everything is dead"))
  end

  def test_hooks_ruby_calls_for_you_are_roots
    %w[const_missing deconstruct_keys _dump method_missing respond_to_missing? inherited].each do |hook|
      assert_includes Graph::FRAMEWORK, hook
    end
  end

  def test_setters_and_index_methods_cannot_be_reached_by_name_and_are_never_reported
    %w[model= [] []=].each { |name| assert_match Graph::UNCALLABLE_BY_NAME, name }
    refute_match Graph::UNCALLABLE_BY_NAME, "model"
  end
end
