require "docile"

result = Docile.with_array([]) do |arr|
  # Add elements
  arr << 1
  arr << 2

  # Remove the last element (2)
  arr.pop

  # Add another element
  arr << 3
end

p result #=> [1, 3]
