# frozen_string_literal: true

if defined?(StimulusReflex::Reflex)
  class ApplicationReflex < StimulusReflex::Reflex
  end
else
  class ApplicationReflex
  end
end