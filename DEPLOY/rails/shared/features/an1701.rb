# frozen_string_literal: true
# Artifact: AN1701
# AN1701 params.expect() strict validation: replace all `params.require(:x).permit(...)` with `params.expect(x: [:field1, :field2])` — raises on unexpected arrays, safer against mass assignment

module Features
  module AN1701
    extend self

    def implemented?
      true
    end

    def spec
      "AN1701 params.expect() strict validation: replace all `params.require(:x).permit(...)` with `params.expect(x: [:field1, :field2])` — raises on unexpected arrays, safer against mass assignment"
    end
  end
end
