
# spec/assistants/lawyer_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/lawyer'

RSpec.describe Lawyer do
  it 'processes input' do
    assistant = Lawyer.new
    expect(assistant.process_input('test')).to include('response')
  end
end
