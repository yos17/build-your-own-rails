# Build Your Own Rails
### Learn Ruby on Rails by building a mini version from scratch

Rails feels like magic. Things just work. But *why* they work is hidden behind layers of abstraction.

This course strips everything away. We build a mini Rails framework from zero — and by the end, you'll understand exactly why Rails works the way it does.

---

## What You'll Build

A working mini web framework called **Tracks** with:
- A router that maps URLs to controllers
- Controllers that handle requests
- Views with ERB templates
- Models with database persistence
- Middleware (logging, sessions)
- A CLI to generate files

All in ~500 lines of Ruby.

## What You'll Learn

- **Ruby metaprogramming**: `method_missing`, `define_method`, `class_eval`, `send`
- **Object-oriented design**: inheritance, mixins, modules, Struct
- **How HTTP works**: requests, responses, status codes
- **Rack**: the interface all Ruby web frameworks share
- **SQL and databases**: from raw SQL to an ORM you built yourself
- **DSLs** (Domain Specific Languages): how `has_many`, `belongs_to`, `get "/"` work

## Structure

```
chapters/
  01_ruby_objects/        — Ruby techniques you MUST know first
  02_routing/             — map URLs to code
  03_controllers/         — handle requests, send responses
  04_views/               — ERB templates and layouts
  05_models/              — ORM: map Ruby objects to database rows
  06_database/            — SQL, migrations, connections
  07_middleware/           — request pipeline, logging, sessions
  08_putting_together/    — assemble everything into a working app

framework/lib/            — the actual mini-Rails code (Tracks)
app/                      — a sample app built on Tracks
```

## Prerequisites

- Basic Ruby (variables, classes, methods)
- Completed the Software Tools Ruby course, OR equivalent comfort with Ruby
- SQLite installed: `brew install sqlite3`
- Ruby 3.x: check with `ruby --version`

---

## The Big Question

Rails has this in `routes.rb`:
```ruby
get "/posts", to: "posts#index"
resources :users
```

And this in a model:
```ruby
class Post < ApplicationRecord
  belongs_to :user
  has_many :comments
end
```

How does `belongs_to` know what to do? How does `get "/"` register a route? Why does the controller method just work when a URL is hit?

By the end of this course, you'll know exactly how — because you'll have built it yourself.
