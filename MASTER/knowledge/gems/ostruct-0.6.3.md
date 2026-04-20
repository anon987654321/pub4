require "ostruct"

person = OpenStruct.new
person.name = "John Smith"
person.age  = 70

person.name # => "John Smith"
person.age  # => 70
person.address # => nil
