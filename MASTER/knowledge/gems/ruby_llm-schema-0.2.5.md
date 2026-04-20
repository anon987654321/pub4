class PersonSchema < RubyLLM::Schema
  string :name, description: "Full name"
  number :age, description: "Age in years", min: 0, max: 120  boolean :active, required: false

  object :address do
    string :street    string :city
    string :country  end

  array :tags, of: :string
  array :contacts, of: object do
    string :email, format: :email
    string :phone
  end

  any_of :status, enum: %w[active pending inactive], null: trueend
