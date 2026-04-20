require "sqlite3"

# Open a database
db = SQLite3::Database.new "test.db"

# Create a table
rows = db.execute <<-SQL
  create table numbers (
    name varchar(30),
    val int
  );
SQL

# Insert rows
{
  "one" => 1,
  "two" => 2,
}.each { |k, v| db.execute "insert into numbers values (?, ?)", [k, v] }

# Select rows
db.execute("select * from numbers") { |row| p row }
# => ["one", 1]
#    ["two", 2]

# Table with multiple columns
db.execute <<-SQL
  create table students (
    name varchar(50),
    email varchar(50),
    grade varchar(5),
    blog varchar(50)
  );
SQL

# Insert with parameters
db.execute(
  "INSERT INTO students (name, email, grade, blog)
   VALUES (?, ?, ?, ?)",
  ["Jane", "me@janedoe.com", "A", "http://blog.janedoe.com"]
)

db.execute("select * from students") { |row| p row }
# => ["Jane", "me@janedoe.com", "A", "http://blog.janedoe.com"]
