# frozen_string_literal: true
# AN208: Pundit authorization

if defined?(Pundit)
  Pundit::NotAuthorizedError.class_eval do
    def initialize(message = "Not authorized")
      super(message)
    end
  end
end