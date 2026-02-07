# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestConstitution < Minitest::Test
  def setup
    MASTER::DB.setup(path: ":memory:")
  end

  def test_constitution_file_exists
    const_file = File.join(MASTER::Paths.data, "constitution.yml")
    assert File.exist?(const_file), "Constitution file should exist"
  end
  
  def test_constitution_loads_successfully
    const = MASTER::Executor.constitution
    refute_nil const, "Constitution should load"
    assert const.is_a?(Hash), "Constitution should be a hash"
  end
  
  def test_constitution_has_safety_policies
    const = MASTER::Executor.constitution
    assert const.key?("safety"), "Constitution should have safety policies"
    assert const["safety"].key?("dangerous_operations"), "Should define dangerous operations"
  end
  
  def test_constitution_has_permissions
    const = MASTER::Executor.constitution
    assert const.key?("permissions"), "Constitution should have permissions"
    assert const["permissions"].key?("shell_command"), "Should define shell_command permissions"
    assert const["permissions"].key?("code_execution"), "Should define code_execution permissions"
    assert const["permissions"].key?("file_write"), "Should define file_write permissions"
  end
  
  def test_constitution_protects_itself
    const = MASTER::Executor.constitution
    blocked_paths = const.dig("permissions", "file_write", "blocked_paths") || []
    assert blocked_paths.include?("data/constitution.yml"), 
           "Constitution should protect itself from writes"
  end
  
  def test_constitution_has_staging_config
    const = MASTER::Executor.constitution
    assert const.key?("staging"), "Constitution should have staging config"
    assert const["staging"]["enabled"], "Staging should be enabled"
  end
end
