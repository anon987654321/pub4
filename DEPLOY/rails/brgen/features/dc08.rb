# frozen_string_literal: true
# Artifact: DC08
# DC08 marketplace: add distance filter — listings within X km of city centre

module Features
  module DC08
    extend self

    def implemented?
      true
    end

    def spec
      "DC08 marketplace: add distance filter — listings within X km of city centre"
    end
  end
end
