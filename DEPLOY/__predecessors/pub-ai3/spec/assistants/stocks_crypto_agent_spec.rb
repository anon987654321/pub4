
# spec/assistants/stocks_crypto_agent_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/stocks_crypto_agent'

RSpec.describe StocksCryptoAgent do
  it 'processes input' do
    assistant = StocksCryptoAgent.new
    expect(assistant.process_input('test')).to include('response')
  end
end
