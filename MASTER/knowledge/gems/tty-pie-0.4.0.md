require "tty-pie"

# Data points for the chart.
# Each hash describes a slice:
#   - :name   – label shown in the legend
#   - :value  – numeric size of the slice
#   - :color  – TTY color symbol (e.g., :bright_yellow)
#   - :fill   – character used to fill the slice
data = [
  { name: "BTC", value: 5_977, color: :bright_yellow,  fill: "*" },
  { name: "BCH", value: 3_045, color: :bright_green,   fill: "x" },
  { name: "LTC", value: 2_030, color: :bright_magenta, fill: "@" },
  { name: "ETH", value: 2_350, color: :bright_cyan,    fill: "+" }
]

# Build the chart. Adjust `radius` to change overall size.
pie_chart = TTY::Pie.new(data: data, radius: 5)

# Render the chart to STDOUT.
print pie_chart
