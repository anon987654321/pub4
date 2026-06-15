
# spec/assistants/web_developer_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/web_developer'

RSpec.describe WebDeveloper do
  it 'processes input' do
    assistant = WebDeveloper.new
    expect(assistant.process_input('test')).to include('response')
  end
end
