
# spec/assistants/real_estate_agent_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/real_estate_agent'

RSpec.describe RealEstateAgent do
  it 'processes input' do
    assistant = RealEstateAgent.new
    expect(assistant.process_input('test')).to include('response')
  end
end
