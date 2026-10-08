# frozen_string_literal: true

module Shared
  # Norwegian kroner first: "kr 3 500" with a thin space as the thousands
  # mark and no dangling ",00". Other currencies keep "3,500.00 USD".
  module MoneyDisplay
    module_function

    def format(cents, currency = "NOK")
      amount = cents.to_i / 100.0
      cur = currency.to_s.upcase
      cur.empty? || cur == "NOK" ? format_nok(amount) : format_generic(amount, cur)
    end

    def format_nok(amount)
      negative = amount.negative?
      amount = amount.abs
      whole = amount.floor
      frac = ((amount - whole) * 100).round
      if frac == 100
        whole += 1
        frac = 0
      end
      grouped = whole.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1\u00A0").reverse
      body = frac.zero? ? grouped : "#{grouped},#{frac.to_s.rjust(2, "0")}"
      "#{negative ? "−" : ""}kr\u00A0#{body}"
    end

    def format_generic(amount, currency)
      sprintf("%.2f %s", amount, currency)
    end
  end
end
