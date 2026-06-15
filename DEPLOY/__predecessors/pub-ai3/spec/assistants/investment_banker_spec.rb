
# spec/assistants/investment_banker_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/investment_banker'

RSpec.describe InvestmentBanker do
  it 'processes input' do
    assistant = InvestmentBanker.new
    expect(assistant.process_input('test')).to include('response')
  end
end
