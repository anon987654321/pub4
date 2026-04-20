OptionParser

Specifies options co-located with handlers.
Generates summary automatically.
Handles optional/mandatory arguments.
Converts arguments to classes.
Constrains argument sets.

Installation
gem install optparse

Usage
require 'optparse'
options = {}
OptionParser.new do |opts|
  opts.on('-v', '--[no-]verbose') { |v| options[:verbose] = v }
end.parse!
p options
p ARGV