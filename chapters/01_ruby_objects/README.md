# Chapter 1 — Ruby Techniques You Must Know

## Why This Chapter Exists

Rails uses Ruby features that most tutorials skip. Things like `method_missing`, `define_method`, `class << self`. These look scary at first. But once you understand them, Rails stops feeling like magic and starts making sense.

This chapter is a fast tour of the Ruby techniques we'll use throughout the course.

---

## 1. Everything is an Object

In Ruby, **everything** is an object. Not just strings and arrays — classes themselves are objects.

```ruby
"hello".class     # => String
42.class          # => Integer
String.class      # => Class
Class.class       # => Class  (yes, Class is an instance of itself!)
```

This means classes can have methods called on them:

```ruby
String.methods.count    # => lots
String.instance_methods # => methods available on strings
```

Why does this matter? Because Rails calls methods on classes all the time:

```ruby
class Post < ApplicationRecord
  belongs_to :user      # this is a method called on the Post CLASS
  validates :title, presence: true  # same
end
```

---

## 2. Open Classes — Adding Methods to Anything

In Ruby, you can reopen any class at any time and add methods:

```ruby
class String
  def shout
    upcase + "!!!"
  end
end

"hello".shout   # => "HELLO!!!"
```

This is called **monkey patching**. Rails uses it constantly:

```ruby
# Rails adds these to Integer:
5.days.ago
3.hours.from_now

# Rails adds these to String:
"hello_world".camelize    # => "HelloWorld"
"User".underscore         # => "user"
"Post".tableize           # => "posts"
```

These aren't built into Ruby — Rails adds them by reopening Integer, String, etc.

---

## 3. Blocks, Procs, and Lambdas

A **block** is a chunk of code you pass to a method:

```ruby
[1, 2, 3].each { |n| puts n }

[1, 2, 3].each do |n|
  puts n * 2
end
```

You can capture a block in a method with `&block` or `yield`:

```ruby
def run_twice
  yield    # run the block
  yield    # run it again
end

run_twice { puts "hello" }
# hello
# hello

# With yield and arguments:
def transform(value)
  yield(value)
end

transform(5) { |n| n * 2 }  # => 10
```

**Proc** — save a block as an object:

```ruby
double = Proc.new { |n| n * 2 }
double.call(5)   # => 10

# Shorthand:
double = proc { |n| n * 2 }
triple = lambda { |n| n * 3 }
square = ->(n) { n ** 2 }    # stabby lambda

square.call(4)   # => 16
square.(4)       # same, shorter
square[4]        # also the same!
```

Why this matters for Rails:

```ruby
# Rails routes use blocks:
Rails.application.routes.draw do
  get "/posts", to: "posts#index"
  resources :users
end

# ActiveRecord uses blocks:
User.where { |u| u.age > 18 }
Post.transaction { ... }
```

---

## 4. `method_missing` — Catching Undefined Methods

When you call a method that doesn't exist, Ruby normally raises `NoMethodError`. But you can intercept this:

```ruby
class Ghost
  def method_missing(name, *args)
    puts "You called '#{name}' with #{args.inspect}"
  end
end

g = Ghost.new
g.anything       # => You called 'anything' with []
g.fly(10, 20)    # => You called 'fly' with [10, 20]
```

This is how Rails does magic like:

```ruby
User.find_by_email("yosia@example.com")
# There's no find_by_email method — method_missing catches it!

User.find_by_name_and_age("Yosia", 30)
# Parses the method name and builds the SQL query
```

Always define `respond_to_missing?` alongside `method_missing`:

```ruby
class Ghost
  def method_missing(name, *args)
    # handle it
  end

  def respond_to_missing?(name, include_private = false)
    true  # or check if name matches your pattern
  end
end
```

---

## 5. `define_method` — Creating Methods Dynamically

Instead of writing 10 similar methods, generate them:

```ruby
class Status
  ["pending", "active", "closed"].each do |state|
    define_method("#{state}?") do
      @state == state
    end

    define_method("#{state}!") do
      @state = state
    end
  end
end

s = Status.new
s.active!
s.active?   # => true
s.closed?   # => false
```

Rails uses this for things like:

```ruby
# attr_accessor is basically:
def self.attr_accessor(*names)
  names.each do |name|
    define_method(name) { @instance_vars[name] }
    define_method("#{name}=") { |val| @instance_vars[name] = val }
  end
end
```

---

## 6. `class_eval` and `instance_eval` — Running Code in a Different Context

```ruby
class Dog; end

Dog.class_eval do
  def bark
    "Woof!"
  end
end

Dog.new.bark  # => "Woof!"
```

`class_eval` opens a class and adds methods to it. Used when you have the class as a variable:

```ruby
klass = User  # or params[:model].constantize in Rails
klass.class_eval do
  def hello
    "Hi from #{self.class}"
  end
end
```

`instance_eval` runs code in the context of an object:

```ruby
obj = Object.new
obj.instance_eval do
  def secret
    "shhh"
  end
end

obj.secret   # => "shhh"
```

This is how Rails routes work:

```ruby
# routes.rb
Rails.application.routes.draw do
  get "/", to: "home#index"   # this block runs with instance_eval
end                           # so 'get' calls self.get on the router
```

---

## 7. `send` — Calling Methods by Name

```ruby
"hello".send(:upcase)       # => "HELLO"
"hello".send(:[], 1)        # => "e"  (same as "hello"[1])

obj.send(:private_method)   # can even call private methods!
```

Why useful? When you have the method name as a string or symbol:

```ruby
action = "index"
controller.send(action)   # calls controller.index
```

Rails does this when routing — it figures out which controller action to call from the URL, then `send`s it.

---

## 8. Modules as Mixins

```ruby
module Greetable
  def greet
    "Hello, I'm #{name}"
  end
end

module Farewell
  def bye
    "Goodbye from #{name}"
  end
end

class Person
  include Greetable
  include Farewell

  attr_reader :name
  def initialize(name)
    @name = name
  end
end

p = Person.new("Yosia")
p.greet  # => "Hello, I'm Yosia"
p.bye    # => "Goodbye from Yosia"
```

Rails uses modules everywhere:

```ruby
class Post < ApplicationRecord
  include Searchable      # adds search methods
  include Taggable        # adds tagging
  include Timestamps      # adds created_at/updated_at tracking
end
```

### `extend` vs `include`

```ruby
include Mod   # adds Mod's methods as INSTANCE methods
extend Mod    # adds Mod's methods as CLASS methods
```

```ruby
module ClassMethods
  def create_table
    # ...
  end
end

class Post
  extend ClassMethods
end

Post.create_table   # works! class method
```

---

## 9. `attr_accessor`, `attr_reader`, `attr_writer`

These are class methods that generate instance methods:

```ruby
class Person
  attr_accessor :name, :age   # generates getter + setter
  attr_reader :id             # generates getter only
  attr_writer :password       # generates setter only
end

# attr_accessor :name is equivalent to:
def name
  @name
end
def name=(val)
  @name = val
end
```

---

## 10. Struct — Quick Value Objects

```ruby
Point = Struct.new(:x, :y)
p = Point.new(3, 4)
p.x   # => 3
p.y   # => 4

# With methods:
Point = Struct.new(:x, :y) do
  def distance_to_origin
    Math.sqrt(x**2 + y**2)
  end
end
```

We'll use Struct for things like `Request` and `Response` in our framework.

---

## Putting It Together — A Taste

Here's a tiny DSL (Domain Specific Language) using these techniques:

```ruby
class Validator
  def initialize
    @rules = []
  end

  def self.validates(field, **options)
    @validations ||= []
    @validations << { field: field, options: options }
  end

  def self.validations
    @validations || []
  end
end

class Post < Validator
  validates :title, presence: true
  validates :body, length: { min: 10 }
end

Post.validations
# => [{field: :title, options: {presence: true}},
#     {field: :body, options: {length: {min: 10}}}]
```

This is almost exactly how Rails `validates` works. It's just a class method that stores configuration in a class-level variable.

---

## Exercises

1. Reopen the `Integer` class and add a `factorial` method. `5.factorial` should return 120.
2. Use `method_missing` to build a `FlexibleHash` that lets you access keys as methods: `h.name` instead of `h[:name]`.
3. Use `define_method` to generate `is_admin?`, `is_user?`, `is_guest?` methods from an array of roles.
4. Build a tiny DSL for defining HTML tags:
   ```ruby
   class HTML
     tag :div, :p, :span, :h1
   end
   HTML.new.div("hello")   # => "<div>hello</div>"
   ```
5. Build `my_attr_accessor` that works exactly like Ruby's built-in.

---

## What You Learned

| Technique | Used in Rails for |
|-----------|------------------|
| Open classes | Adding `.days`, `.ago`, `.camelize` to built-in types |
| Blocks/procs | Route definitions, callbacks, scopes |
| `method_missing` | `find_by_*`, dynamic finders |
| `define_method` | Generating accessor, scope, and callback methods |
| `class_eval` | Adding methods to classes at runtime |
| `send` | Dispatching to controller actions by name |
| Modules/mixins | Concerns, shared behavior between models |
| Struct | Value objects for requests, responses |
