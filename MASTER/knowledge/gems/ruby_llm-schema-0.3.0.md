class PersonSchema < RubyLLM::Schema
  string :name, description: "Full name"
  number :age, description: "Age in years", min: 0, max: 120
  boolean :active, required: false

  object :address do
    string :street
    string :city
    string :country, required: false
  end

  array :tags, of: :string
  
  array :contacts do
    object do
      string :email, format: "email"
      string :phone, required: false
    end
  end

  any_of :status, enum: ["active", "pending", "inactive"], null: true
end

schema = PersonSchema.new
puts schema.to_json
