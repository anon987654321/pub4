
# spec/assistants/doctor_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/doctor'

RSpec.describe Doctor do
  it 'processes input' do
    assistant = Doctor.new
    expect(assistant.process_input('test')).to include('response')
  end
end
