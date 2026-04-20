class Person
  include ActiveModel::API
  attr_accessor :name, :age
  validates_presence_of :nameend

person = Person.new(name: 'bob', age: '18')
person.valid?   # => true
person.errors.full_messages
# => []
