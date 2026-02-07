# frozen_string_literal: true

# Stage protocol: contract for all pipeline stages

module MASTER
  module Stage
    def call(input)
      raise NotImplementedError, "#{self.class} must implement #call"
    end

    def skip?(input)
      false
    end

    def name
      self.class.name.split("::").last.downcase
    end
  end
end
