require "tty-box"

# Create a framed box containing the text "Hello world!"
#   padding: 3  – adds three spaces around the content
#   align:  :center – centers the text horizontally
box = TTY::Box.frame "Hello world!", padding: 3, align: :center

# Render the box to STDOUT
puts box
