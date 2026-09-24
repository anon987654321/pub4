# frozen_string_literal: true

module Operator
  module StorefrontArt
    module_function

    def rules
      MasterDesign.design_system.fetch("storefront_art")
    end

    def prompt(vertical:, subject:)
      template = rules.fetch("prompt_template")
      template
        .gsub("{vertical}", vertical.to_s)
        .gsub("{subject}", subject.to_s)
    end

    def spec(vertical:)
      rules
        .fetch("palette")
        .fetch(vertical.to_s)
        .then { |palette| rules.merge("palette" => palette) }
    end
  end
end
