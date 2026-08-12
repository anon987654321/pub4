# frozen_string_literal: true

require "json"

# DILLA_FROZEN=1 — read the learned state, write none of it.
#
# The engine learns. session.json carries the performer, the groove and the
# generation counter; learned_engine.json carries what the source study found;
# promoted_profiles.json carries which profiles earned their place; the vocal
# and chop catalogues carry what has been ingested. All of it is read on the
# next run and all of it changes what comes out.
#
# That is the point of the feature and it is also why two renders of the same
# command are not the same render. Trying to A/B a change means holding
# everything else still, and this engine could not: a comparison take rendered
# before and after a refactor differed because session.json had moved between
# them, not because the refactor did anything. That comparison was abandoned
# rather than published, which is the honest outcome and a bad one -- it means
# the refactor shipped unmeasured.
#
# So: frozen reads exactly as before and writes nothing back. Renders still
# differ from each other by seed; what stops moving is the accumulated state
# underneath them. Every skipped write is announced once, because a mode that
# silently drops data would be a worse bug than the one it fixes.
#
# Not a substitute for RENDER_SEED. Seed pins the dice; this pins the table.
module DillaFrozen
  class << self
    def on? = ENV["DILLA_FROZEN"] == "1"

    # Every persistent-state write goes through here. Returns true when it
    # wrote, false when frozen -- callers that report a path to the operator
    # need to know which happened.
    def write(path, content)
      unless on?
        File.write(path, content)
        return true
      end

      skipped(path)
      false
    end

    def write_json(path, data)
      write(path, "#{JSON.pretty_generate(data)}\n")
    end

    # What a run declined to write. Recorded so provenance can say the render
    # was made against held state rather than leaving that to be inferred.
    def skips = @skips ||= []

    def skipped(path)
      short = path.to_s.sub("#{File.expand_path('..', __dir__)}/", "")
      return if skips.include?(short)

      skips << short
      warn "frozen: not writing #{short} (DILLA_FROZEN=1)"
    end

    def reset! = @skips = []
  end
end
