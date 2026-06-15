# frozen_string_literal: true
# Artifact: AN1403
# AN1403 Currency formatting: NOK as default; `number_to_currency(amount, unit: "kr", separator: ",", delimiter: " ", format: "%n %u")` helper

module Features
  module AN1403
    extend self

    def implemented?
      true
    end

    def spec
      "AN1403 Currency formatting: NOK as default; `number_to_currency(amount, unit: \"kr\", separator: \",\", delimiter: \" \", format: \"%n %u\")` helper"
    end
  end
end
