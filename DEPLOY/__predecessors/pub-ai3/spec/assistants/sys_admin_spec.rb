
# spec/assistants/sys_admin_spec.rb
require 'spec_helper'
require_relative '../../lib/assistants/sys_admin'

RSpec.describe SysAdmin do
  it 'processes input' do
    assistant = SysAdmin.new
    expect(assistant.process_input('test')).to include('response')
  end
end
