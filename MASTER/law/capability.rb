# frozen_string_literal: true

# A reduced cognitive context keeps its authority reduced, just as pledge(2)
# never lets a process reacquire a promise it has dropped. unveil(2) is sealed
# after setup, and the trusted runtime narrows stage 1 into stage 2.
Law.define(:CAPABILITY_REDUCTION_IS_MONOTONIC) do
  path "MASTER/lib/core.rb"
  source "OpenBSD pledge(2) and unveil(2) design grammar extended to MASTER"
  ask "Can a capability context or process phase regain authority after it has been dropped or locked? Reduced contexts must remain reduced; new authority requires a new trusted context."
  practice "A security restriction is a one-way door: later phases may narrow the boundary further, never widen it."
  fix "Do not reacquire capabilities. Seal filesystem visibility and syscall promises after setup; create a new trusted context or process when a genuinely different authority set is required."
  bad <<~'X'
    capabilities.drop(:network)
    capabilities.acquire(:network)
  X
  good <<~'X'
    capabilities.drop(:network)
    # network remains unavailable
  X
  detect { |line| line.match?(/\b(?:capabilities|@capabilities)\.acquire\s*\(/) }
end
