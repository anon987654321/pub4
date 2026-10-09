# frozen_string_literal: true

module Shared
  # Locates MASTER/contracts for the repo checkout and for the deploy copy-tree,
  # where __shared sits beside app/ under /home/<app> and MASTER is outside it.
  # PUB4_ROOT (exported by rc.d and vps_ci.sh) names the checkout that holds
  # MASTER; without it, the repo root is four levels above this file.
  module Contracts
    module_function

    def root
      configured = ENV["PUB4_ROOT"].to_s.strip
      configured.empty? ? File.expand_path("../../../..", __dir__) : configured
    end

    def dir
      File.join(root, "MASTER", "contracts")
    end

    # MASTER/tools holds the plain-Ruby audits the shared test examples run.
    def tool_path(name)
      File.join(root, "MASTER", "tools", name.to_s)
    end

    def require_contract(name)
      require File.join(dir, name.to_s)
    end
  end
end
