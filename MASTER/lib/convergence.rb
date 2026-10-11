# frozen_string_literal: true

require_relative "boot/paths"

module Master
  # Convergence is the non-authoritative measurement/proof plane for the
  # assistant wishlist. Constitution and product behaviour remain owned by
  # their existing sources; this namespace only reports what the tree can prove.
  module Convergence
    VERSION = 1
    ROOTS = MasterPaths::TREES
    STATES = %i[landed partial evidence operator missing rejected].freeze
  end
end
