require "reline"

prompt = "prompt> "
use_history = true

begin
  loop do
    text = Reline.readmultiline(prompt, use_history) do |input|
      input.split.last == "end"
    end

    puts "You entered:"
    puts text
  end
rescue Interrupt
  puts "^C"
  exit
end
