# frozen_string_literal: true

# A reduced cognitive context keeps its authority reduced, just as pledge(2)
# never lets a process reacquire a promise it has dropped.
Law.define(:CAPABILITY_REDUCTION_IS_MONOTONIC) do
  source "OpenBSD pledge(2) design grammar extended to MASTER"
  severity :error
  languages %i[ruby]
  path "MASTER/lib/core/capabilities.rb"
  ask "Can a capability context regain authority after it has been dropped or locked? Reduced contexts must remain reduced; new authority requires a new trusted context."
  fix "Do not reacquire capabilities. Create a new trusted context when a genuinely different authority set is required."
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
