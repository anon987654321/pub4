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
# This file lives here rather than inside its callers because it has two, in
# different trees: MASTER/test/test_helper.rb and STUDIO's
# dilla/lib/music_gems.rb, which requires it by absolute path right after
# `require "coltrane"`.
#
# It was merged into test_helper.rb on 2026-08-2x under the note "its only
# reader is this helper", and dilla's require then raised LoadError. That
# require sits inside load_gem's `rescue LoadError`, so coltrane was marked
# unavailable and the engine fell back to inline theory — a silent change to
# what dilla renders, found only because two tests in test:dilla went red and
# stayed red. Deleting this file again costs the same thing, so grep both trees
# before believing a reader count.
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
