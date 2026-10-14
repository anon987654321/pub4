# frozen_string_literal: true

require "minitest/autorun"
load File.expand_path("../usr/local/sbin/pub4-admin", __dir__)

class Pub4AdminTest < Minitest::Test
  ADMIN = Pub4Admin

  def test_service_action_maps_to_fixed_argv
    assert_equal ["/usr/sbin/rcctl", "restart", "brgen"],
                 ADMIN.command_for(%w[service restart brgen])
    assert_equal ["/usr/sbin/rcctl", "check", "master"],
                 ADMIN.command_for(%w[service check master])
  end

  def test_only_known_service_targets_are_admitted
    %w[master brgen amber bsdports brgen_jobs amber_jobs bsdports_jobs].each do |service|
      refute_nil ADMIN.command_for(["service", "check", service])
    end

    assert_nil ADMIN.command_for(%w[service restart relayd])
    assert_nil ADMIN.command_for(%w[service restart sshd])
    assert_nil ADMIN.command_for(["service", "restart", "../root"])
  end

  def test_service_verb_and_argument_shape_are_closed
    assert_nil ADMIN.command_for(%w[service set brgen flags arbitrary])
    assert_nil ADMIN.command_for(%w[service shell brgen])
    assert_nil ADMIN.command_for(%w[service restart brgen extra])
    assert_nil ADMIN.command_for(%w[service restart])
    assert_nil ADMIN.command_for(%w[run sh -c id])
    assert_nil ADMIN.command_for(%w[stamp brgen abc1234 ok])
  end

  def test_started_service_inventory_is_a_fixed_read_operation
    assert_equal ["/usr/sbin/rcctl", "ls", "started"],
                 ADMIN.command_for(%w[service list-started])
  end

  def test_started_services_are_filtered_to_the_broker_allowlist
    output = "sshd\nrelay d\nmaster\nbrgen\ncron\nbsdports_jobs\n"

    assert_equal "master\nbrgen\nbsdports_jobs",
                 ADMIN.filter_started_services(output)
  end

  def test_privileged_action_set_excludes_service_configuration_mutation
    refute_includes ADMIN::SERVICE_ACTIONS, "enable"
    refute_includes ADMIN::SERVICE_ACTIONS, "disable"
    refute_nil ADMIN.command_for(%w[service restart brgen])
    assert_nil ADMIN.command_for(%w[service enable brgen])
    assert_nil ADMIN.command_for(%w[service disable brgen])
  end

  def test_root_script_does_not_evaluate_shell_command_strings
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))

    refute_match(/system\s*\(|Open3\.|Process\.spawn|%x/, source)
    assert_includes source, "exec(*command)"
    assert_includes source, 'raise "must run as root through doas" unless Process.euid.zero?'
  end

  def test_privileged_helpers_must_be_root_owned_and_non_writable
    source = File.read(File.expand_path("../usr/local/sbin/pub4-admin", __dir__))

    assert_includes source, "stat.uid.zero? && (stat.mode & 0o022).zero?"
    assert_includes source, "trusted_script!(RESOURCE_GUARD)"
    assert_includes source, "trusted_script!(SOLID_QUEUE_PROOF)"
  end
end
