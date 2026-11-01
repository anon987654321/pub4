# frozen_string_literal: true

# Minitest 5 with its mock, for the tests here that stub. Minitest 6 is the
# default gem on this Ruby and no longer ships minitest/mock, so `.stub` raised
# NoMethodError in every such test. Plugins are off because an installed
# railties registers one that cannot load outside a Rails app.
# tool_test_helper.rb pins the same way for the tool suites.
ENV["MT_NO_PLUGINS"] = "1"
gem "minitest", "~> 5.25"
require "minitest/autorun"
require "minitest/mock"
