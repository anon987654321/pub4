
# spec/egpt_spec.rb
require 'spec_helper'

RSpec.describe EGPT do
  it 'lists all available assistants' do
    egpt = EGPT.new
    expect { egpt.list_assistants }.to output(/Available Assistants/).to_stdout
  end

  it 'shows help message' do
    egpt = EGPT.new
    expect { egpt.show_help }.to output(/EGPT Command Line Interface/).to_stdout
  end
end
