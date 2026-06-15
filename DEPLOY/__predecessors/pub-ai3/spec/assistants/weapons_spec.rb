
# spec/assistants/weapons_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/weapons'

RSpec.describe Weapons do
  it 'processes input' do
    assistant = Weapons.new
    expect(assistant.process_input('test')).to include('response')
  end
end
