
# spec/assistants/musicians_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/musicians'

RSpec.describe Musicians do
  it 'processes input' do
    assistant = Musicians.new
    expect(assistant.process_input('test')).to include('response')
  end
end
