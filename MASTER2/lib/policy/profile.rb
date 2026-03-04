# frozen_string_literal: true

require_relative "../mode"
require_relative "../capabilities"

module MASTER
  module Policy
    # Maps a detected intent to a capability floor and a human-readable profile name.
    # Applied once per pipeline.call, after IntentClassifier.detect.
    #
    # Profile semantics:
    #   :ops      — sysadmin work; floor=execute(3) so shell tools are available
    #   :refactor — code transformation; floor=write(2), branch safety enforced
    #   :chat     — conversation; floor=propose(1), read-only tooling
    #   :doc      — documentation; floor=propose(1)
    #   :creative — generative; floor=propose(1), no system claims allowed
    #
    # The floor is a *minimum* — user can escalate beyond it via --apply/--exec/MASTER_CAP.
    # It is never a ceiling; profiles express what is needed, not what is forbidden above.
    module Profile
      PROFILES = {
        Mode::OPS      => { name: "ops",      capability_floor: Capabilities::LEVELS[:execute] },
        Mode::REFACTOR => { name: "refactor", capability_floor: Capabilities::LEVELS[:write]   },
        Mode::CHAT     => { name: "chat",     capability_floor: Capabilities::LEVELS[:propose]  },
        Mode::DOC      => { name: "doc",      capability_floor: Capabilities::LEVELS[:propose]  },
        Mode::CREATIVE => { name: "creative", capability_floor: Capabilities::LEVELS[:propose]  },
      }.freeze

      DEFAULT = PROFILES[Mode::CHAT].freeze

      class << self
        # Apply the profile for a given intent:
        #   - raises Capabilities.level to the floor if current level is below it
        #   - logs the active profile
        #   - returns the profile hash
        def apply(intent)
          profile = PROFILES.fetch(intent, DEFAULT)
          floor   = profile[:capability_floor]

          if Capabilities.level < floor
            Capabilities.level = floor
            Logging.dmesg_log(
              "policy_profile",
              message: "intent=#{intent} profile=#{profile[:name]} cap_floor=#{floor} (#{Capabilities::LEVEL_NAMES[floor]})",
            )
          end

          profile
        end

        def for_intent(intent)
          PROFILES.fetch(intent, DEFAULT)
        end
      end
    end
  end
end
