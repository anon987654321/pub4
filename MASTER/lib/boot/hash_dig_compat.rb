# frozen_string_literal: true

# Coltrane 2.1.5 replaces Hash#dig with
#
#   args.size > 1 ? self[args.shift].dig(*args) : self[args[0]]
#
# which calls .dig on the intermediate instead of short-circuiting, so any
# missing key raises NoMethodError where MRI returns nil. It is defined
# directly on Hash, so it wins for the whole process the moment coltrane is
# required — every `dig` in every gem and every app, not just the caller's.
#
# Prepending restores MRI's behaviour without needing the original C method
# back, and it is idempotent so repeated bootstraps are free.
#
# It is installed only where coltrane is loaded: MASTER/tools's
# dilla/lib/music_gems.rb requires it by absolute path right after
# `require "coltrane"`, and MASTER never loads coltrane, so neither MASTER's
# boot nor its test suite installs it. test_master_boot proves it in a child
# process.
#
# That require sits inside load_gem's `rescue LoadError`, so a missing file
# marks coltrane unavailable and the engine falls back to inline theory — a
# silent change to what dilla renders. Moving or deleting this file breaks a
# reader in another tree; `bin/operator readers` finds it where a grep of
# MASTER does not.
module Master
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
