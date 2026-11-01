# frozen_string_literal: true

if defined?(StimulusReflex::Reflex)
  class ApplicationReflex < Shared::ApplicationReflex
  end
else
  class ApplicationReflex
  end
end
