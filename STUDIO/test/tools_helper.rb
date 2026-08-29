# frozen_string_literal: true
#
# repligen and postpro are single-file tools. Both guard their CLI, so `load`
# under a changed $PROGRAM_NAME defines everything and runs nothing. They load
# in a separate process from dilla (see Rakefile) because all three define
# top-level constants and several names collide.

require_relative "studio_helper"

module Studio
  module Tools
    # `load`, not `require_relative`: the guard compares __FILE__ to
    # $PROGRAM_NAME, and $PROGRAM_NAME has to already be something else when
    # the comparison runs.
    def self.load_tool(relative)
      original = $PROGRAM_NAME
      $PROGRAM_NAME = "studio_test_probe"
      load File.join(Studio::ROOT, relative)
    ensure
      $PROGRAM_NAME = original
    end
  end
end
