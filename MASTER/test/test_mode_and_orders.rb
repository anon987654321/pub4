# frozen_string_literal: true

require_relative "test_helper"

# Standing orders and the command modules. Each test pins a
# specific failure, not the general shape.
class TestModeAndOrders < Minitest::Test
  # Every dispatcher reopens one module, and Ruby resolves two same-named
  # methods in it silently: the later load wins. Nothing may repeat a name.
  def test_no_dispatch_method_is_defined_twice_across_the_command_modules
    root = File.expand_path("../lib/cli", __dir__)
    owners = Hash.new { |h, k| h[k] = [] }
    paths = [File.join(root, "command_registry.rb")] + Dir.glob(File.join(root, "command_registry", "*.rb"))
    paths.each do |path|
      source = File.read(path)
      next unless source.include?("module CommandRegistry")

      source.scan(/^\s*def (dispatch_\w+)/) { |(name)| owners[name] << File.basename(path) }
    end

    refute_empty owners, "expected to find dispatch_* methods to check"
    duplicated = owners.select { |_, files| files.size > 1 }
    assert_empty duplicated, "same dispatch name defined in two files; the later load silently wins: #{duplicated}"
  end

  # Ground::Orders::Backup existed, was reachable by no key, and pointed three
  # directories above MASTER instead of one.
  def test_backup_order_is_registered
    assert_equal Master::Ground::Orders::Backup, Master::Ground::Orders::Registry.lookup("backup")
  end

  def test_every_declared_callable_resolves_to_a_class
    orders = Master.load_yaml(Master.state_path)
    keys = Array(orders).filter_map { |order| order["callable"] if order.is_a?(Hash) }

    refute_empty keys
    keys.each do |key|
      refute_nil Master::Ground::Orders::Registry.lookup(key),
                 "data/state.yml declares callable: #{key} with no Registry entry"
    end
  end

  def test_backup_source_is_the_repo_root_not_its_grandparent
    Dir.mktmpdir do |repo|
      master = File.join(repo, "MASTER")
      FileUtils.mkdir_p(master)
      order = Master::Ground::Orders::Backup.new(container: { root: master })

      assert_equal File.realpath(repo), File.realpath(order.source_root)
    end
  end
end
