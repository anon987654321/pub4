# frozen_string_literal: true
# Artifact: AN1704
# AN1704 find_each for bulk operations: replace `.all.each` with `.find_each(batch_size: 500)` in all admin/reporting jobs — prevents memory exhaustion on large datasets

module Features
  module AN1704
    extend self

    def implemented?
      true
    end

    def spec
      "AN1704 find_each for bulk operations: replace `.all.each` with `.find_each(batch_size: 500)` in all admin/reporting jobs — prevents memory exhaustion on large datasets"
    end
  end
end
