
# spec/assistants/seo_expert_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/seo_expert'

RSpec.describe SeoExpert do
  it 'processes input' do
    assistant = SeoExpert.new
    expect(assistant.process_input('test')).to include('response')
  end
end
