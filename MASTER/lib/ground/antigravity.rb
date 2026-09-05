# frozen_string_literal: true

require_relative "antigravity/json_config"
require_relative "antigravity/discovery"
require_relative "antigravity/skills"

module Master
  module Ground
    # Reads the skills an Antigravity workspace declares — `.agents/skills/`,
    # a `skills.json` and its inherits chain, and the global and built-in roots
    # under `~/.gemini` — so `Cli::Skills` can offer them beside MASTER's own.
    # That is the whole surface: skills in, skill hashes out.
    #
    # It is an adapter to somebody else's on-disk format
    # (https://antigravity.google/docs/home/), not a second skills system, and
    # nothing here decides anything. The `agy` provider in `data/providers.yml`
    # is a different subject that shares the name — that one is an LLM reached
    # by executing a binary.
    module Antigravity
    end
  end
end
