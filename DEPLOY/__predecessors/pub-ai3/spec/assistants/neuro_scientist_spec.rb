
# spec/assistants/neuro_scientist_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/neuro_scientist'

RSpec.describe NeuroScientist do
  it 'processes input' do
    assistant = NeuroScientist.new
    expect(assistant.process_input('test')).to include('response')
  end
end
