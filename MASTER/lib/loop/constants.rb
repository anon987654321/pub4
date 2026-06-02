# frozen_string_literal: true

module Master
  module Loop
    module Constants
      TRANSIENT_RE = /429|throttl|rate.?limit|high demand|provider.?error|overload|capacity|503/i.freeze
      PERMANENT_RE = /syntax|missing dependency|permission denied|schema violation|enoent|eacces/i.freeze
      AMBIGUOUS_RE = /partial write|half.?committed|unknown|conflict/i.freeze
    end
  end
end
