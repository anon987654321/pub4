require 'rainbow'

# ----------------------------------------------------------------------
# Example: Build a styled message using Rainbow’s chainable API.
# ----------------------------------------------------------------------
# Rainbow works by wrapping a *plain* string, then chaining colour,
# background, and style helpers.  The helpers return a new Rainbow object,
# so you can keep appending text while preserving the current styles.
#
# In this snippet we:
#   1. Start with the word “red”.
#   2. Colour it red.
#   3. Append plain text.
#   4. Switch the background to yellow for the next fragment.
#   5. Append more text that inherits the yellow background.
#   6. Finish with an underlined, bright segment.
#
# The final string is printed to STDOUT with all styles applied.

message =
  Rainbow('red')                     # base string
    .red                             # foreground colour
    .append(' and ')                 # plain text
    .bg(:yellow)                     # set background for following text
    .append('yellow background')    # inherits the yellow background
    .append(' and ')                 # more plain text (still on yellow bg)
    .underline                       # underline the next fragment
    .bright('underlined!')           # bright/bold + underline

puts message
