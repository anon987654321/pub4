
# spec/assistants/advanced_propulsion_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/advanced_propulsion'

RSpec.describe AdvancedPropulsion do
  it 'processes input' do
    assistant = AdvancedPropulsion.new
    expect(assistant.process_input('test')).to include('response')
  end
end
