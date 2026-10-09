# frozen_string_literal: true

module Shared
  # Locates MASTER/contracts for the repo checkout and for the deploy copy-tree,
  # where __shared sits beside app/ under /home/<app> and MASTER is outside it.
  # PUB4_ROOT (exported by rc.d and vps_ci.sh) names the checkout that holds
  # MASTER; without it, the repo root is four levels above this file.
  module Contracts
    module_function

    def dir
      root = ENV["PUB4_ROOT"].to_s.strip
      root = File.expand_path("../../../..", __dir__) if root.empty?
      File.join(root, "MASTER", "contracts")
    end

    def require_contract(name)
      require File.join(dir, name.to_s)
    end
  end
end
