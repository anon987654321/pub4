
# spec/assistants/psychological_warfare_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/psychological_warfare'

RSpec.describe PsychologicalWarfare do
  it 'processes input' do
    assistant = PsychologicalWarfare.new
    expect(assistant.process_input('test')).to include('response')
  end
end
