# Chapter 5 — Models: Your Data in Ruby

## What is an ORM?

ORM = **Object-Relational Mapper**. It's the layer between your Ruby objects and the database.

Without an ORM:
```ruby
db.execute("SELECT * FROM posts WHERE id = ?", [5])
# => [{"id"=>5, "title"=>"Hello", "body"=>"..."}]
# You get back a raw hash. You do everything manually.
```

With an ORM (like ActiveRecord):
```ruby
Post.find(5)
# => #<Post id=5, title="Hello", body="...">
# You get back a Post object with methods.
```

The ORM also lets you:
- `post.save` → runs INSERT or UPDATE
- `post.destroy` → runs DELETE
- `Post.where(author: "Yosia")` → generates SELECT with WHERE clause

Let's build a simple one.

---

## The Design

Our ORM, called **Track::Model**, will:
1. Know which database table it maps to (from the class name)
2. Know its column names (by querying the database)
3. Map columns to Ruby attributes automatically
4. Provide `find`, `all`, `where`, `save`, `destroy`

```ruby
class Post < Tracks::Model
  # That's it. Everything else is automatic.
end

Post.all           # SELECT * FROM posts
Post.find(5)       # SELECT * FROM posts WHERE id = 5 LIMIT 1
Post.where(title: "Hello")  # SELECT * FROM posts WHERE title = 'Hello'

post = Post.new(title: "Hi", body: "World")
post.save          # INSERT INTO posts (title, body) VALUES ('Hi', 'World')

post.title = "Updated"
post.save          # UPDATE posts SET title = 'Updated' WHERE id = 1
post.destroy       # DELETE FROM posts WHERE id = 1
```

---

## Building the Base Model

```ruby
# framework/lib/tracks/model.rb

require 'sqlite3'

module Tracks
  class Model
    # --- Class-level state ---

    def self.table_name
      # Post → "posts", UserProfile → "user_profiles"
      name.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '') + 's'
    end

    def self.db
      @@db ||= SQLite3::Database.new("db/development.sqlite3")
      @@db.results_as_hash = true
      @@db
    end

    def self.columns
      # Ask the database what columns this table has
      @columns ||= db.execute("PRAGMA table_info(#{table_name})")
        .map { |col| col["name"] }
    end

    # --- Querying ---

    def self.all
      rows = db.execute("SELECT * FROM #{table_name}")
      rows.map { |row| new(row) }
    end

    def self.find(id)
      row = db.execute(
        "SELECT * FROM #{table_name} WHERE id = ? LIMIT 1", [id]
      ).first
      raise "Record not found: #{table_name} ##{id}" unless row
      new(row)
    end

    def self.find_by(conditions)
      where_clause = conditions.keys.map { |k| "#{k} = ?" }.join(" AND ")
      values       = conditions.values
      row = db.execute(
        "SELECT * FROM #{table_name} WHERE #{where_clause} LIMIT 1", values
      ).first
      row ? new(row) : nil
    end

    def self.where(conditions)
      where_clause = conditions.keys.map { |k| "#{k} = ?" }.join(" AND ")
      values       = conditions.values
      rows = db.execute(
        "SELECT * FROM #{table_name} WHERE #{where_clause}", values
      )
      rows.map { |row| new(row) }
    end

    def self.count
      db.execute("SELECT COUNT(*) as count FROM #{table_name}").first["count"]
    end

    # --- Creating instances ---

    def initialize(attrs = {})
      @attributes = {}
      # Set attributes from hash (database row or user-provided hash)
      attrs.each do |key, value|
        @attributes[key.to_s] = value
      end
      # Define getter/setter methods for each column
      define_attribute_methods
    end

    def define_attribute_methods
      self.class.columns.each do |col|
        # Getter: post.title
        define_singleton_method(col) { @attributes[col] }
        # Setter: post.title = "Hello"
        define_singleton_method("#{col}=") { |v| @attributes[col] = v }
      end
    end

    # --- Persistence ---

    def new_record?
      @attributes["id"].nil?
    end

    def save
      if new_record?
        insert
      else
        update
      end
    end

    def destroy
      self.class.db.execute(
        "DELETE FROM #{self.class.table_name} WHERE id = ?", [@attributes["id"]]
      )
    end

    def persisted?
      !new_record?
    end

    def to_h
      @attributes.dup
    end

    private

    def insert
      cols   = @attributes.keys.reject { |k| k == "id" }
      values = cols.map { |k| @attributes[k] }
      placeholders = cols.map { "?" }.join(", ")

      self.class.db.execute(
        "INSERT INTO #{self.class.table_name} (#{cols.join(', ')}) VALUES (#{placeholders})",
        values
      )
      @attributes["id"] = self.class.db.last_insert_row_id
      true
    end

    def update
      cols   = @attributes.keys.reject { |k| k == "id" }
      values = cols.map { |k| @attributes[k] }
      set_clause = cols.map { |k| "#{k} = ?" }.join(", ")

      self.class.db.execute(
        "UPDATE #{self.class.table_name} SET #{set_clause} WHERE id = ?",
        values + [@attributes["id"]]
      )
      true
    end
  end
end
```

---

## Associations — `belongs_to` and `has_many`

This is the really fun part. How does Rails know that `post.user` hits the database?

```ruby
class Post < ApplicationRecord
  belongs_to :user
  has_many :comments
end
```

`belongs_to` and `has_many` are **class methods** that define instance methods dynamically. Let's build them:

```ruby
module Tracks
  module Associations
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # belongs_to :user
      # Generates: post.user → User.find(post.user_id)
      def belongs_to(name)
        define_method(name) do
          foreign_key = "#{name}_id"
          related_class = Object.const_get(name.to_s.capitalize)
          related_class.find(@attributes[foreign_key])
        end

        define_method("#{name}=") do |obj|
          @attributes["#{name}_id"] = obj&.id
        end
      end

      # has_many :comments
      # Generates: post.comments → Comment.where(post_id: post.id)
      def has_many(name)
        define_method(name) do
          # "comments" → Comment
          related_class = Object.const_get(name.to_s.chomp("s").capitalize)
          foreign_key   = "#{self.class.table_name.chomp('s')}_id"
          related_class.where(foreign_key => @attributes["id"])
        end
      end

      # has_many :comments, through: :post_comments
      # (left as exercise — requires a join query)

      # belongs_to :user with custom foreign key
      # belongs_to :author, class_name: "User", foreign_key: "author_id"
      def belongs_to(name, class_name: nil, foreign_key: nil)
        foreign_key   ||= "#{name}_id"
        related_class_name = class_name || name.to_s.capitalize

        define_method(name) do
          related_class = Object.const_get(related_class_name)
          related_class.find(@attributes[foreign_key])
        end

        define_method("#{name}=") do |obj|
          @attributes[foreign_key] = obj&.id
        end
      end
    end
  end
end

# Include in base model:
class Tracks::Model
  include Tracks::Associations
end
```

Now:

```ruby
class Post < Tracks::Model
  belongs_to :user
  has_many :comments
end

post = Post.find(1)
post.user       # => User object — SQL: SELECT * FROM users WHERE id = ?
post.comments   # => [Comment, ...] — SQL: SELECT * FROM comments WHERE post_id = ?
```

This is **exactly** what Rails does. `belongs_to` is just a class method that calls `define_method` to add instance methods that know how to query related data.

---

## Validations

```ruby
module Tracks
  module Validations
    def self.included(base)
      base.extend(ClassMethods)
      base.instance_variable_set(:@validations, [])
    end

    module ClassMethods
      def validates(field, **rules)
        @validations << { field: field, rules: rules }
      end

      def validations
        @validations
      end
    end

    def valid?
      @errors = {}
      self.class.validations.each do |v|
        field = v[:field].to_s
        value = @attributes[field]
        rules = v[:rules]

        if rules[:presence] && (value.nil? || value.to_s.strip.empty?)
          add_error(field, "can't be blank")
        end

        if rules[:length]
          min = rules[:length][:min]
          max = rules[:length][:max]
          add_error(field, "is too short (min #{min})") if min && value.to_s.length < min
          add_error(field, "is too long (max #{max})")  if max && value.to_s.length > max
        end

        if rules[:uniqueness]
          existing = self.class.find_by(field => value)
          add_error(field, "must be unique") if existing && existing.id != @attributes["id"]
        end
      end

      @errors.empty?
    end

    def errors
      @errors ||= {}
    end

    def save
      return false unless valid?
      super
    end

    private

    def add_error(field, message)
      @errors[field] ||= []
      @errors[field] << message
    end
  end
end
```

```ruby
class Post < Tracks::Model
  include Tracks::Validations

  belongs_to :user
  validates :title, presence: true, length: { min: 3, max: 100 }
  validates :body, presence: true
end

post = Post.new(title: "Hi")
post.valid?             # => false
post.errors             # => {"title" => ["is too short (min 3)"], "body" => ["can't be blank"]}
post.save               # => false (doesn't hit DB)
```

---

## `self.included(base)` — How Modules Hook Into Classes

You've seen this pattern twice now:

```ruby
module SomeMixin
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def some_class_method; end
  end
end
```

When you `include SomeMixin` in a class, Ruby automatically calls `SomeMixin.included(TheClass)`. We use this to also `extend` the class with class methods.

This is **one of the most common patterns in Rails**. It's how Concerns, Validations, Callbacks, and Associations add both class methods and instance methods when you include them.

---

## Exercises

1. Add `order`: `Post.order("created_at DESC")` → adds `ORDER BY` to the query.
2. Add `limit`: `Post.limit(10)` → adds `LIMIT 10`. Bonus: chain it: `Post.where(active: true).limit(5)`.
3. Add `has_one`: like `has_many` but returns a single object.
4. Add `before_save` callback: `before_save :set_slug` calls a method before INSERT/UPDATE.
5. Add `after_create` callback that fires only after a successful INSERT.

---

## What You Learned

| Concept | Key point |
|---------|-----------|
| ORM | maps Ruby objects to DB rows |
| `table_name` | derived from class name automatically |
| `PRAGMA table_info` | ask SQLite what columns a table has |
| `define_singleton_method` | add methods to a single object instance |
| `belongs_to` / `has_many` | class methods that use `define_method` to add query methods |
| `self.included(base)` | hook called when module is included — used to add class methods |
| Validations | run before save, set errors, return false to prevent save |
| `||=` | initialize if nil — lazy loading pattern |
