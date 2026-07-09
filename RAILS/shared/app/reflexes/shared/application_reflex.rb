# frozen_string_literal: true

module Shared
  if defined?(StimulusReflex::Reflex)
    class ApplicationReflex < StimulusReflex::Reflex
    end
  end
end