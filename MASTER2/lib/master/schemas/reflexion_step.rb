module MASTER
  module Schemas
    REFLEXION_STEP = {
      type: "object",
      required: ["thought"],
      properties: {
        thought: { type: "string" },
        critique: { type: "string" },
        improvement: { type: "string" }
      }
    }
  end
end
