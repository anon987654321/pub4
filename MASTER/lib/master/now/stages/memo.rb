# frozen_string_literal: true

module Master
  module Now
  module Stages
    # Compatibility name. Use Memory for new code.
    Memo = Memory unless const_defined?(:Memo, false)
  end
  end
end