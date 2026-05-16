# frozen_string_literal: true

module Master
  module Loop
    module Constants
      TRANSIENT_RE = /429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i.freeze
    end
  end
end
