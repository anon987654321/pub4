# frozen_string_literal: true

require_relative "test_helper"

# Every command the registry builds must be able to run, and the built surface,
# the help pages and the module's tables must describe one set of verbs.
#
# Command#call ends in `@receiver.public_send(@method_name, ...)`, so a symbol
# that names no public method fails when a person types the verb rather than
# when the registry is built. The command tables that `build` never merged are
# deleted; the third test keeps a new one from arriving unmerged.
class TestCommandRegistryDispatch < Minitest::Test
  Registry = Master::CLI::CommandRegistry

  def built
    @built ||= Registry.build(
      infra: { session: Master::Trace::Session.new, config: {}, root: Master::ROOT, bus: nil },
      ai: { agent: nil },
      root: Master::ROOT,
    )
  end

  def test_every_built_command_names_a_public_method
    unresolvable = built.filter_map do |verb, command|
      name = command.method_name
      "/#{verb} -> #{name}" unless name.nil? || Registry.respond_to?(name)
    end

    assert_operator built.size, :>=, 10, "a registry this small means build broke, not that the surface shrank"
    assert_empty unresolvable, "these verbs dispatch to a method nothing answers: #{unresolvable.join(', ')}"
  end

  # A verb with no page is a command nobody can find, and a page with no verb
  # sends the reader to type something the router cannot resolve.
  def test_help_pages_and_the_built_surface_are_one_set
    assert_equal built.keys.sort, Registry::HELP_TOPICS.keys.sort
  end

  # A `*_commands` method is a table of verbs. Only control_commands exists,
  # and build merges it; slash_commands is the help list, not a table.
  def test_device_and_hardware_commands_have_distinct_routes
    assert_equal :dispatch_device_agent, built.fetch("device").method_name
    assert Registry.respond_to?(:dispatch_device)
    assert Registry.respond_to?(:dispatch_device_agent)
  end

  def test_critique_is_a_documented_discoverable_command
    assert built.key?("critique")
    assert_includes Registry::HELP_TOPICS.keys, "critique"
    assert_includes Registry.slash_commands, "/critique"
    assert_match(%r{/critique}, Registry.help_text("critique"))
    assert_equal :dispatch_critique, built.fetch("critique").method_name
  end

  def test_no_command_table_is_left_unmerged
    tables = Registry.singleton_methods.map(&:to_s).grep(/_commands\z/) - %w[slash_commands]

    assert_equal %w[control_commands], tables.sort,
                 "a new command table has to be merged by build, or it is a verb with no route"
  end

  def test_session_commands_are_one_verb
    assert_equal :dispatch_session, built.fetch("session").method_name
    %w[sessions continue resume fork].each { |gone| refute built.key?(gone), "/#{gone} is /session #{gone}" }
    assert_includes Registry.help_text("session"), "/session fork"
  end
end
