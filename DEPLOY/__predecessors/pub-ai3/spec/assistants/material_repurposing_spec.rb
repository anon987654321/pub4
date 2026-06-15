
# spec/assistants/material_repurposing_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/material_repurposing'

RSpec.describe MaterialRepurposing do
  it 'processes input' do
    assistant = MaterialRepurposing.new
    expect(assistant.process_input('test')).to include('response')
  end
end
