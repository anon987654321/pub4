#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "bplan/validate"

class ValidateTest < Minitest::Test
  def setup
    @root = File.expand_path("..", __dir__)
  end

  def test_validate_all_passes
    errors = Bplan::Validate.validate_all(root: @root)
    assert_empty errors, errors.join("\n")
  end

  def test_funding_budgets_converge
    errors = Bplan::Validate.validate_funding(@root)
    assert_empty errors, errors.join("\n")
  end

  def test_manifest_and_html_present
    errors = Bplan::Validate.validate_legats(@root)
    assert_empty errors, errors.join("\n")
  end

  def test_batches_reference_known_ids
    errors = Bplan::Validate.validate_batches(@root)
    assert_empty errors, errors.join("\n")
  end
end