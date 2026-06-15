
# spec/assistants/real_estate_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/real_estate'

RSpec.describe RealEstate do
  it 'processes input' do
    assistant = RealEstate.new
    expect(assistant.process_input('test')).to include('response')
  end
end
