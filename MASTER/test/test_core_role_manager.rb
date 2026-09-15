# frozen_string_literal: true

require "minitest/autorun"

# Base module setup
module Master
  ROOT = "/Users/mac/Documents/GitHub/pub4/pub4-convergence"
  module Core; module Routing; end; end
  module Core; module Execution; end; end
end

require_relative "../lib/core/routing/model_catalog"
require_relative "../lib/core/execution/roles"
require_relative "../lib/core/execution/role_manager"

# Mock ModelRouter
class MockRouter
  def preferred(task_type: nil)
    case task_type
    when :architecture then "strong-reasoner"
    when :coding then "gemma-4-26b"
    when :review then "independent-validator"
    else "default-model"
    end
  end
end

class TestRoleManager < Minitest::Test
  def setup
    @router = MockRouter.new
    @container = { model_router: @router }
    @manager = Master::Core::Execution::RoleManager.new(router: @router, container: @container)
  end

  def test_default_role_resolution
    assert_equal "strong-reasoner", @manager.model_for(Master::Core::Execution::Roles::ARCHITECT)
    assert_equal "gemma-4-26b", @manager.model_for(Master::Core::Execution::Roles::IMPLEMENTER)
    assert_equal "independent-validator", @manager.model_for(Master::Core::Execution::Roles::VALIDATOR)
  end

  def test_role_override
    # We bypass the actual resolve logic by mocking the catalog or providing a canonical ID
    # that ModelCatalog.resolve simply returns (as per its logic for canonical IDs)
    @manager.override(Master::Core::Execution::Roles::IMPLEMENTER, "ollama:local-qwen")
    assert_equal "ollama:local-qwen", @manager.model_for(Master::Core::Execution::Roles::IMPLEMENTER)
  end

  def test_active_roles_map
    roles = @manager.active_roles
    assert_equal "strong-reasoner", roles[Master::Core::Execution::Roles::ARCHITECT]
    assert_equal "gemma-4-26b", roles[Master::Core::Execution::Roles::IMPLEMENTER]
  end
end
