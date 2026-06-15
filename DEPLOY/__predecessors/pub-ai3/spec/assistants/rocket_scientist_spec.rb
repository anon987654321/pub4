
# spec/assistants/rocket_scientist_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/rocket_scientist'

RSpec.describe RocketScientist do
  it 'processes input' do
    assistant = RocketScientist.new
    expect(assistant.process_input('test')).to include('response')
  end
end
