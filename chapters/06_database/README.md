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
