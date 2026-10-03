# frozen_string_literal: true

module Dilla
  module ProcessSpawn
    module_function

    def options(options = {})
      result = options.dup
      result[:close_others] = true unless result.key?(:close_others)
      result
    end
  end
end
