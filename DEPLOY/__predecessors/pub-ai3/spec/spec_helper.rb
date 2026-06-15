
# spec/spec_helper.rb
require 'rspec'
require 'factory_bot'
require_relative '../lib/egpt'

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
end
