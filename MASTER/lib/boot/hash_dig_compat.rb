# frozen_string_literal: true

module Master
  # Coltrane 2.x replaces Hash#dig with a variant that calls .dig on nil
  # intermediates. Restore MRI-compatible nil-short-circuit chaining.
  module HashDigCompat
    def dig(*keys)
      keys.reduce(self) do |obj, key|
        break nil unless obj.respond_to?(:[])

        obj[key]
      end
    end
  end

  module_function

  def install_hash_dig_compat!
    return if Hash.ancestors.first == HashDigCompat

    Hash.prepend(HashDigCompat)
  end
end
