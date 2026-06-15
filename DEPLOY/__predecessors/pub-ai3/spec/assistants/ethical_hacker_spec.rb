
# spec/assistants/ethical_hacker_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/ethical_hacker'

RSpec.describe EthicalHacker do
  it 'processes input' do
    assistant = EthicalHacker.new
    expect(assistant.process_input('test')).to include('response')
  end
end
