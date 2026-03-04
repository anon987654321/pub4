# frozen_string_literal: true

require_relative "test_helper"

class TestBridgesPostpro < Minitest::Test
  def test_stocks_constant_is_hash
    assert_kind_of Hash, MASTER::Bridges::PostproBridge::STOCKS
    refute_empty MASTER::Bridges::PostproBridge::STOCKS
  end

  def test_stocks_includes_common_film_stocks
    stocks = MASTER::Bridges::PostproBridge::STOCKS
    assert stocks.key?(:kodak_portra)
    assert stocks.key?(:fuji_velvia)
    assert stocks.key?(:tri_x)
  end

  def test_each_stock_has_required_keys
    MASTER::Bridges::PostproBridge::STOCKS.each do |name, params|
      assert params.key?(:grain),    "#{name} missing :grain"
      assert params.key?(:gamma),    "#{name} missing :gamma"
      assert params.key?(:feeling),  "#{name} missing :feeling"
    end
  end

  def test_prints_constant_is_hash
    assert_kind_of Hash, MASTER::Bridges::PostproBridge::PRINTS
    refute_empty MASTER::Bridges::PostproBridge::PRINTS
  end

  def test_lenses_constant_is_hash
    assert_kind_of Hash, MASTER::Bridges::PostproBridge::LENSES
    refute_empty MASTER::Bridges::PostproBridge::LENSES
  end

  def test_apply_preset_returns_error_for_nonexistent_file
    result = MASTER::Bridges::PostproBridge.apply_preset(
      "/nonexistent/image.jpg",
      preset: :portrait
    )
    assert result.err?
  end

  def test_apply_random_returns_error_for_nonexistent_file
    result = MASTER::Bridges::PostproBridge.apply_random(
      "/nonexistent/image.jpg"
    )
    assert result.err?
  end
end
