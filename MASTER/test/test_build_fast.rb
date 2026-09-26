# frozen_string_literal: true

require_relative "test_helper"

class TestCanonicalBootSurface < Minitest::Test
  def test_builder_has_one_build_entrypoint
    assert_respond_to Master::Builder, :build
    refute_respond_to Master::Builder, :build_fast
  end

  def test_master_has_one_boot_entrypoint
    assert_respond_to Master, :boot
    refute_respond_to Master, :boot_fast
  end
end
