
# spec/assistants/sound_mastering_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/sound_mastering'

RSpec.describe SoundMastering do
  it 'processes input' do
    assistant = SoundMastering.new
    expect(assistant.process_input('test')).to include('response')
  end
end
