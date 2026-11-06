# frozen_string_literal: true
# instrument: code_lines=12 longest_method=1 public_methods=1 namespace_lines=4

# Zeitwerk maps a path to a constant, so lib/ground/policy/sandbox.rb must open
# Master, then Ground, then Policy before it can say anything. Those wrappers
# carry no implementation and the file will not resolve without them.
#
# Master and Ground are wrappers here: each holds exactly one module, so each
# costs two of the four. Policy is not — it holds a constant as well as the
# class, which is work. That is the whole distinction, and it is why the count
# parses rather than matching `module` at the start of a line.
module Master
  module Ground
    module Policy
      TIERS = %i[deny ask allow].freeze

      class Sandbox
        def decide(command)
          command.to_s.empty? ? :ask : :allow
        end
      end
    end
  end
end
