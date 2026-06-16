# 1️⃣  Create an empty OpenStruct
person = OpenStruct.new

# 2️⃣  Add arbitrary attributes
person.name = "John Smith"
person.age  = 70

# 3️⃣  Read them back
person.name  # => "John Smith"
person.age   # => 70

# 4️⃣  Missing keys are safe – they return +nil+ instead of raising
person.address # => nil
