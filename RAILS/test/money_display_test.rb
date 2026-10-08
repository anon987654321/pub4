# frozen_string_literal: true

require "minitest/autorun"
require_relative "../shared/app/models/concerns/shared/money_display"

class MoneyDisplayTest < Minitest::Test
  M = Shared::MoneyDisplay

  def test_whole_kroner_drop_the_decimal
    assert_equal "kr\u00A03\u00A0500", M.format(350_000)
  end

  def test_ore_use_a_comma
    assert_equal "kr\u00A059,50", M.format(5950)
  end

  def test_other_currencies_keep_the_iso_code
    assert_equal "12.00 USD", M.format(1200, "USD")
  end
end
