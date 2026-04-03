# Chapter 6 — The Database Layer

## SQL First — Then Abstractions

Before ORM magic, there's SQL. And Rails' ORM is just Ruby building SQL strings and executing them. Understanding SQL makes the ORM less mysterious.

---

## SQLite — The Perfect Learning Database

SQLite is a database in a single file. No server, no setup.

```bash
brew install sqlite3      # macOS
sqlite3 db/development.sqlite3   # open a database (creates if not exists)
```

Basic SQLite shell:
```sql
.tables          -- list tables
.schema posts    -- show CREATE TABLE for posts
.quit            -- exit
```

---

## SQL Fundamentals

### Create a table

```sql
CREATE TABLE posts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  body TEXT,
  user_id INTEGER,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id)
);
```

### Insert

```sql
INSERT INTO posts (title, body, user_id)
VALUES ('Hello World', 'This is my first post', 1);
```

### Select

```sql
SELECT * FROM posts;
SELECT id, title FROM posts WHERE user_id = 1;
SELECT * FROM posts ORDER BY created_at DESC LIMIT 10;
SELECT * FROM posts WHERE title LIKE '%Ruby%';
```

### Update

```sql
UPDATE posts SET title = 'Updated Title' WHERE id = 5;
```

### Delete

```sql
DELETE FROM posts WHERE id = 5;
```

### Joins

```sql
-- Get posts with their author names:
SELECT posts.title, users.name AS author
FROM posts
INNER JOIN users ON posts.user_id = users.id;

-- Posts with comment count:
SELECT posts.title, COUNT(comments.id) AS comment_count
FROM posts
LEFT JOIN comments ON comments.post_id = posts.id
GROUP BY posts.id;
```

---

## Migrations — Version Control for Your Database

A **migration** is a Ruby file that describes a database change. Rails applies them in order, and tracks which ones have run.

```ruby
# db/migrations/001_create_posts.rb

class CreatePosts
  def up
    db.execute(<<-SQL)
      CREATE TABLE posts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT,
        user_id INTEGER,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    SQL
  end

  def down
    db.execute("DROP TABLE posts")
  end
end
```

`up` applies the change. `down` reverses it.

Let's build a migration runner:

```ruby
# framework/lib/tracks/migrator.rb

module Tracks
  class Migrator
    MIGRATIONS_TABLE = "schema_migrations"
    MIGRATIONS_DIR   = "db/migrations"

    def initialize(db)
      @db = db
      ensure_migrations_table
    end

    def migrate
      pending = pending_migrations
      if pending.empty?
        puts "Nothing to migrate."
        return
      end

      pending.each do |file|
        version = File.basename(file, ".rb")
        puts "Running migration: #{version}"

        require_relative File.expand_path("../../../#{file}", __FILE__)
        class_name = version.gsub(/^\d+_/, '').split('_').map(&:capitalize).join
        klass = Object.const_get(class_name)
        migration = klass.new(@db)
        migration.up

        @db.execute("INSERT INTO #{MIGRATIONS_TABLE} (version) VALUES (?)", [version])
        puts "  ✅ Done: #{version}"
      end
    end

    def rollback
      last = @db.execute(
        "SELECT version FROM #{MIGRATIONS_TABLE} ORDER BY version DESC LIMIT 1"
      ).first
      return puts "Nothing to rollback." unless last

      version = last["version"]
      puts "Rolling back: #{version}"
      require File.join(MIGRATIONS_DIR, "#{version}.rb")
      # ... (similar to migrate, but calls .down)
    end

    private

    def ensure_migrations_table
      @db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS #{MIGRATIONS_TABLE} (
          version TEXT PRIMARY KEY,
          applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      SQL
    end

    def pending_migrations
      applied = @db.execute("SELECT version FROM #{MIGRATIONS_TABLE}")
        .map { |r| r["version"] }

      Dir.glob("#{MIGRATIONS_DIR}/*.rb").sort.reject do |f|
        applied.include?(File.basename(f, ".rb"))
      end
    end
  end
end
```

---

## Connection Pooling — A Note

In development, one database connection is fine. In production, many requests come in simultaneously. Each one needs its own connection (SQLite is single-writer, but production apps use PostgreSQL or MySQL which support concurrent connections).

Rails' ActiveRecord uses a **connection pool** — a set of pre-opened connections shared among threads:

```
Request 1 → gets connection A → queries → returns connection A to pool
Request 2 → gets connection B → queries → returns connection B to pool
Request 3 → waits if pool is full...
```

Our mini ORM uses a single shared connection — fine for learning, not for production.

---

## Query Builder — Building SQL Programmatically

You might want to chain conditions:

```ruby
Post.where(active: true).order("created_at DESC").limit(10)
```

This requires a **query builder** — an object that accumulates SQL fragments and executes them lazily.

```ruby
# framework/lib/tracks/query.rb

module Tracks
  class Query
    def initialize(model_class)
      @model = model_class
      @conditions  = []
      @values      = []
      @order_clause = nil
      @limit_count  = nil
    end

    def where(conditions)
      conditions.each do |k, v|
        @conditions << "#{k} = ?"
        @values << v
      end
      self   # return self for chaining!
    end

    def order(clause)
      @order_clause = clause
      self
    end

    def limit(n)
      @limit_count = n
      self
    end

    def to_sql
      sql = "SELECT * FROM #{@model.table_name}"
      sql += " WHERE #{@conditions.join(' AND ')}" unless @conditions.empty?
      sql += " ORDER BY #{@order_clause}" if @order_clause
      sql += " LIMIT #{@limit_count}"    if @limit_count
      sql
    end

    def to_a
      rows = @model.db.execute(to_sql, @values)
      rows.map { |row| @model.new(row) }
    end

    # Make it behave like an array
    include Enumerable
    def each(&block)
      to_a.each(&block)
    end

    def first
      limit(1).to_a.first
    end

    def count
      sql = "SELECT COUNT(*) as count FROM #{@model.table_name}"
      sql += " WHERE #{@conditions.join(' AND ')}" unless @conditions.empty?
      @model.db.execute(sql, @values).first["count"]
    end
  end
end
```

Now update the model to return `Query` objects:

```ruby
class Tracks::Model
  def self.where(conditions)
    Query.new(self).where(conditions)
  end

  def self.order(clause)
    Query.new(self).order(clause)
  end

  def self.limit(n)
    Query.new(self).limit(n)
  end
end
```

Now chaining works:
```ruby
Post.where(user_id: 1).order("created_at DESC").limit(5).each do |post|
  puts post.title
end
```

The SQL is only built and executed when you actually iterate (`.each`) or call `.to_a`. This is called **lazy evaluation** — Rails does the same.

---

## Transactions

Transactions ensure all-or-nothing database operations:

```ruby
def self.transaction(&block)
  db.transaction(&block)
rescue => e
  db.rollback
  raise e
end
```

```ruby
Tracks::Model.transaction do
  user.save!
  account.save!
  # If account.save! fails, user.save! is also rolled back
end
```

---

## Sample Migration Files

```ruby
# db/migrations/001_create_users.rb
class CreateUsers
  def initialize(db); @db = db; end

  def up
    @db.execute(<<-SQL)
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_digest TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    SQL
  end

  def down
    @db.execute("DROP TABLE IF EXISTS users")
  end
end

# db/migrations/002_create_posts.rb
class CreatePosts
  def initialize(db); @db = db; end

  def up
    @db.execute(<<-SQL)
      CREATE TABLE IF NOT EXISTS posts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT,
        user_id INTEGER NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    SQL
  end

  def down
    @db.execute("DROP TABLE IF EXISTS posts")
  end
end
```

---

## Exercises

1. Add `add_column` migration helper that generates `ALTER TABLE ... ADD COLUMN ...`
2. Build a `seeds.rb` file that inserts sample data, and a `rake db:seed` task to run it.
3. Add SQL injection protection — what happens if someone passes `"'; DROP TABLE posts; --"` as a param? Why are `?` placeholders safe?
4. Implement `find_or_create_by`: `User.find_or_create_by(email: "test@example.com")`
5. Add support for `has_many through:` — querying through a join table.

---

## Solutions

### Exercise 1 — `add_column` migration helper

```ruby
# db/migrations/003_add_published_to_posts.rb
class AddPublishedToPosts
  def initialize(db)
    @db = db
  end

  def up
    # SQLite supports a limited ALTER TABLE — only ADD COLUMN
    @db.execute("ALTER TABLE posts ADD COLUMN published INTEGER DEFAULT 0")
    @db.execute("ALTER TABLE posts ADD COLUMN published_at DATETIME")
    puts "Added 'published' and 'published_at' columns to posts"
  end

  def down
    # SQLite doesn't support DROP COLUMN directly.
    # Workaround: recreate the table without the column.
    @db.execute(<<-SQL)
      CREATE TABLE posts_backup AS
        SELECT id, title, body, user_id, created_at FROM posts
    SQL
    @db.execute("DROP TABLE posts")
    @db.execute("ALTER TABLE posts_backup RENAME TO posts")
    puts "Removed 'published' and 'published_at' columns from posts"
  end
end

# You can also add a reusable helper to your Migrator:
# framework/lib/tracks/migrator.rb — add helper methods

module Tracks
  class Migrator
    def add_column(table, column, type, default: nil, null: true)
      sql = "ALTER TABLE #{table} ADD COLUMN #{column} #{type}"
      sql += " DEFAULT #{default}" unless default.nil?
      sql += " NOT NULL" unless null
      @db.execute(sql)
    end

    def remove_column(table, column)
      # SQLite workaround: copy table without the column
      columns = @db.execute("PRAGMA table_info(#{table})")
        .map { |c| c["name"] }
        .reject { |c| c == column.to_s }

      col_list = columns.join(", ")
      @db.execute("CREATE TABLE #{table}_new AS SELECT #{col_list} FROM #{table}")
      @db.execute("DROP TABLE #{table}")
      @db.execute("ALTER TABLE #{table}_new RENAME TO #{table}")
    end
  end
end
```

### Exercise 2 — `seeds.rb` and `rake db:seed`

```ruby
# db/seeds.rb — sample data for development

require_relative "../framework/lib/tracks"
require_relative "../app/models/user"
require_relative "../app/models/post"

puts "Seeding database..."

# Clear existing data
Tracks::Model.db.execute("DELETE FROM posts")
Tracks::Model.db.execute("DELETE FROM users")

# Create users
yosia = User.new(
  name:            "Yosia",
  email:           "yosia@example.com",
  password_digest: "password"
)
yosia.save
puts "Created user: #{yosia.name} (##{yosia.id})"

alice = User.new(
  name:            "Alice",
  email:           "alice@example.com",
  password_digest: "password"
)
alice.save
puts "Created user: #{alice.name} (##{alice.id})"

# Create posts
[
  { title: "Getting Started with Ruby",      body: "Ruby is a dynamic language..." },
  { title: "Building Web Apps from Scratch", body: "Today we'll build a framework..." },
  { title: "Understanding Rack",             body: "Rack is the foundation of..." }
].each do |attrs|
  post = Post.new(attrs.merge(user_id: yosia.id))
  post.save
  puts "Created post: #{post.title} (##{post.id})"
end

puts "Seeding complete! #{User.count} users, #{Post.count} posts."
```

```ruby
# Rakefile — rake tasks for database management

require_relative "framework/lib/tracks"

namespace :db do
  desc "Run pending migrations"
  task :migrate do
    db = Tracks::Model.db
    migrator = Tracks::Migrator.new(db)
    migrator.migrate
  end

  desc "Rollback the last migration"
  task :rollback do
    db = Tracks::Model.db
    migrator = Tracks::Migrator.new(db)
    migrator.rollback
  end

  desc "Seed the database with sample data"
  task :seed do
    load "db/seeds.rb"
  end

  desc "Drop, recreate, migrate, and seed"
  task :reset => [:drop, :migrate, :seed]

  task :drop do
    db_path = ENV["DATABASE_PATH"] || "db/development.sqlite3"
    File.delete(db_path) if File.exist?(db_path)
    puts "Database dropped."
  end
end

# Run with: rake db:migrate
#            rake db:seed
#            rake db:reset
```

### Exercise 3 — SQL injection protection

```ruby
# Demonstration of why parameterized queries are safe
# Run this standalone to see the difference:

require 'sqlite3'

db = SQLite3::Database.new(":memory:")
db.results_as_hash = true
db.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)")
db.execute("INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')")
db.execute("INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com')")

# DANGEROUS — string interpolation allows SQL injection:
def unsafe_find(db, email)
  # An attacker can pass: "' OR '1'='1" to return ALL rows
  # Or: "'; DROP TABLE users; --" to destroy data
  db.execute("SELECT * FROM users WHERE email = '#{email}'")
end

# SAFE — parameterized query:
def safe_find(db, email)
  # The ? is replaced safely; special chars are escaped automatically
  db.execute("SELECT * FROM users WHERE email = ?", [email])
end

# Attack attempt:
attack = "' OR '1'='1"
puts "UNSAFE with attack input:"
puts unsafe_find(db, attack).inspect
# => Returns ALL rows! Attacker bypassed the WHERE clause.

puts "\nSAFE with attack input:"
puts safe_find(db, attack).inspect
# => [] — no results. The literal string is treated as data, not SQL.

# Tracks always uses ? placeholders — this is already safe by design:
# Model.find(id)             → "SELECT ... WHERE id = ?" [id]
# Model.where(email: value)  → "SELECT ... WHERE email = ?" [value]
# model.save                 → "INSERT ... VALUES (?, ...)" [vals]
```

### Exercise 4 — `find_or_create_by`

```ruby
# framework/lib/tracks/model.rb — add find_or_create_by class method

module Tracks
  class Model
    # Find a record matching conditions, or create it if not found.
    # Returns the existing or newly created record.
    # Returns [record, created?] when called with block variant.
    #
    # User.find_or_create_by(email: "test@example.com")
    # User.find_or_create_by(email: "test@example.com") { |u| u.name = "Test" }
    def self.find_or_create_by(conditions)
      existing = find_by(conditions)
      return existing if existing

      record = new(conditions)
      yield record if block_given?
      record.save
      record
    end

    # Raise if creation fails validation:
    def self.find_or_create_by!(conditions)
      existing = find_by(conditions)
      return existing if existing

      record = new(conditions)
      yield record if block_given?
      record.save!
      record
    end
  end
end

# Usage:
# File: app/controllers/sessions_controller.rb
class SessionsController < Tracks::BaseController
  def create
    # Find existing user or create one (OAuth-style flow)
    user = User.find_or_create_by(email: params["email"]) do |u|
      u.name            = params["name"] || "New User"
      u.password_digest = params["password"]
    end

    if user.persisted?
      session[:user_id] = user.id
      redirect_to "/posts"
    else
      @error = "Could not sign in: #{user.errors.inspect}"
      render :new
    end
  end
end

# More examples:
tag = Tag.find_or_create_by(name: "ruby")
puts tag.id   # existing id or newly assigned id

category = Category.find_or_create_by(slug: "tech") do |c|
  c.name = "Technology"
end
```

### Exercise 5 — `has_many through:` (join table)

```ruby
# framework/lib/tracks/associations.rb — extend has_many with through: support

module Tracks
  module Associations
    module ClassMethods
      def has_many(name, class_name: nil, foreign_key: nil, through: nil, source: nil)
        if through
          # has_many :tags, through: :post_tags
          # Joins via the intermediate table
          join_association  = through.to_s          # "post_tags"
          target_class_name = class_name || name.to_s.chomp("s").capitalize  # "Tag"
          source_name       = source || name.to_s.chomp("s")  # "tag"

          define_method(name) do
            # Get all join records (e.g. post.post_tags)
            join_records = send(join_association)
            # Extract the related records (e.g. tag)
            join_records.map { |jr| jr.send(source_name) }
          end
        else
          # Standard has_many (existing behaviour)
          klass = class_name  || name.to_s.chomp("s").capitalize
          fk    = foreign_key || "#{self.name.downcase}_id"

          define_method(name) do
            Object.const_get(klass).where(fk => @attributes["id"])
          end
        end
      end
    end
  end
end

# Usage — a Post can have many Tags through PostTag join model:
#
# Database schema:
#   posts:      id, title, body
#   tags:       id, name
#   post_tags:  id, post_id, tag_id

# File: app/models/post_tag.rb
class PostTag < Tracks::Model
  belongs_to :post
  belongs_to :tag
end

# File: app/models/post.rb
class Post < Tracks::Model
  has_many :post_tags
  has_many :tags, through: :post_tags   # post.tags → all Tag objects

  belongs_to :user
end

# File: app/models/tag.rb
class Tag < Tracks::Model
  has_many :post_tags
  has_many :posts, through: :post_tags  # tag.posts → all Post objects
end

# In use:
post = Post.find(1)
puts post.tags.map(&:name).inspect  # => ["ruby", "rails", "web"]

tag = Tag.find_by(name: "ruby")
puts tag.posts.map(&:title).inspect # => ["Getting Started with Ruby", ...]
```

---

## What You Learned

| Concept | Key point |
|---------|-----------|
| SQL | the language databases actually speak |
| SQLite | single-file database, perfect for development |
| Migrations | versioned, reversible database changes |
| Query builder | accumulates SQL fragments, executes lazily |
| Method chaining | `self` return value enables `.where.order.limit` |
| Lazy evaluation | SQL executed only when results are needed |
| Transactions | all-or-nothing operations |
| SQL injection | why `?` placeholders are always safer than string interpolation |
