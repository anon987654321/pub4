# 1️⃣ Enter the example directory
cd 3_1_customer_support_ticket_agent

# 2️⃣ Install gem dependencies (once)
bundle install

# 3️⃣ Copy the environment template
cp env.example .env

# 4️⃣ Populate your API key
#   Open .env in your editor and replace the placeholder:
#   GOOGLE_AI_API_KEY=your_key_here
$EDITOR .env   # <-- edit and save

# 5️⃣ Run the demo
ruby run.rb
