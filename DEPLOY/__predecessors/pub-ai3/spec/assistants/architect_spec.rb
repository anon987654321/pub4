
# spec/assistants/architect_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/architect'

RSpec.describe Architect do
  it 'processes input' do
    assistant = Architect.new
    expect(assistant.process_input('test')).to include('response')
  end
end
