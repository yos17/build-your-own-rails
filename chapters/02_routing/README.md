# Chapter 2 — Routing: How URLs Map to Code

## What is a Router?

A router answers one question: **"given this URL and HTTP method, which code should run?"**

When someone visits `GET /posts/5`, your app needs to:
1. Match the URL pattern `/posts/:id`
2. Extract the parameter `id = 5`
3. Call `PostsController#show`

That's a router. Let's build one.

---

## First: What is HTTP?

HTTP is a text protocol. A request looks like this:

```
GET /posts/5 HTTP/1.1
Host: localhost:3000
Accept: text/html
```

Line 1: **method** (`GET`) + **path** (`/posts/5`) + version
Then headers. Then (for POST) a body.

HTTP methods:
| Method | Meaning |
|--------|---------|
| GET | Fetch data (read-only) |
| POST | Create something new |
| PUT/PATCH | Update something |
| DELETE | Delete something |

Rails `routes.rb` maps method+path to controller#action:
```ruby
get    "/posts",     to: "posts#index"   # GET /posts → PostsController#index
post   "/posts",     to: "posts#create"  # POST /posts → PostsController#create
get    "/posts/:id", to: "posts#show"    # GET /posts/5 → PostsController#show
```

---

## What is Rack?

Before building our router, we need to understand **Rack**.

Rack is a simple contract that all Ruby web frameworks share. Any Ruby web framework (Rails, Sinatra, Hanami) is ultimately a Rack app. This means:

1. Your app is an object that responds to `call`
2. `call` receives a hash called `env` (the HTTP request)
3. `call` returns `[status_code, headers, body]`

```ruby
# The simplest possible Rack app:
app = ->(env) {
  [200, {"Content-Type" => "text/html"}, ["Hello, World!"]]
}
```

That's it. `200` = OK, headers hash, body array of strings.

To run it:
```ruby
# Gemfile
gem 'rack'

# config.ru (Rack's config file)
require_relative 'app'
run MyApp.new
```

```bash
bundle exec rackup   # starts server on port 9292
```

Rails is a sophisticated Rack app. Sinatra is a simpler one. Ours will be somewhere in between.

---

## Building the Router

Here's our plan:
1. Store routes as an array of `{method, pattern, handler}` objects
2. When a request comes in, find the matching route
3. Extract URL parameters (`:id`, `:slug`)
4. Call the handler

```ruby
# framework/lib/tracks/router.rb

module Tracks
  class Router
    Route = Struct.new(:method, :pattern, :controller, :action)

    def initialize
      @routes = []
    end

    # Called like: get "/posts", to: "posts#index"
    def get(path, to:)
      add_route("GET", path, to)
    end

    def post(path, to:)
      add_route("POST", path, to)
    end

    def patch(path, to:)
      add_route("PATCH", path, to)
    end

    def delete(path, to:)
      add_route("DELETE", path, to)
    end

    def draw(&block)
      # Run the block in our context, so 'get', 'post' etc. call our methods
      instance_eval(&block)
    end

    def route_for(method, path)
      @routes.each do |route|
        next unless route.method == method
        params = match(route.pattern, path)
        return route, params if params
      end
      nil
    end

    private

    def add_route(method, path, to)
      controller, action = to.split("#")
      @routes << Route.new(method, path, controller, action)
    end

    # Match "/posts/:id" against "/posts/5"
    # Returns { "id" => "5" } or nil
    def match(pattern, path)
      # Convert "/posts/:id" to a regex: /^\/posts\/(?<id>[^\/]+)$/
      regex_string = pattern
        .gsub(/:[a-z_]+/) { |match| "(?<#{match[1..]}>([^/]+))" }
      regex = Regexp.new("^#{regex_string}$")

      m = path.match(regex)
      return nil unless m

      # Extract named captures as a hash
      m.named_captures
    end
  end
end
```

Let's test this:

```ruby
router = Tracks::Router.new

router.draw do
  get  "/",          to: "home#index"
  get  "/posts",     to: "posts#index"
  get  "/posts/:id", to: "posts#show"
  post "/posts",     to: "posts#create"
end

route, params = router.route_for("GET", "/posts/42")
puts route.controller  # => "posts"
puts route.action      # => "show"
puts params            # => {"id" => "42"}
```

---

## The Key Technique: `instance_eval`

Notice this in `draw`:
```ruby
def draw(&block)
  instance_eval(&block)
end
```

Without `instance_eval`:
```ruby
router.draw do
  get "/posts", to: "posts#index"  # ERROR: 'get' is not defined here
end
```

With `instance_eval`, the block runs **as if it were inside the router object**. So `get` calls `self.get` which is `router.get`. This is exactly how Rails routes work.

This pattern — running a block in a different context — is how most Ruby DSLs work.

---

## URL Parameter Extraction

The key line in `match`:

```ruby
regex_string = pattern
  .gsub(/:[a-z_]+/) { |match| "(?<#{match[1..]}>([^/]+))" }
```

Let's trace through it:
```
Pattern: "/posts/:id/comments/:comment_id"

After gsub:
  "/posts/(?<id>([^/]+))/comments/(?<comment_id>([^/]+))"

As regex (wrapped in ^ and $):
  /^\/posts\/(?<id>([^\/]+))\/comments\/(?<comment_id>([^\/]+))$/

Match against: "/posts/5/comments/42"
Named captures: { "id" => "5", "comment_id" => "42" }
```

`(?<name>...)` is a **named capture group** in Ruby regex. `m.named_captures` returns them as a hash. Clean!

---

## RESTful Routes — `resources`

Rails has `resources :posts` which generates 7 routes at once. Let's build it:

```ruby
def resources(name)
  # name = :posts → "posts"
  resource_name = name.to_s
  controller    = resource_name

  get    "/#{resource_name}",          to: "#{controller}#index"
  get    "/#{resource_name}/new",      to: "#{controller}#new"
  post   "/#{resource_name}",          to: "#{controller}#create"
  get    "/#{resource_name}/:id",      to: "#{controller}#show"
  get    "/#{resource_name}/:id/edit", to: "#{controller}#edit"
  patch  "/#{resource_name}/:id",      to: "#{controller}#update"
  delete "/#{resource_name}/:id",      to: "#{controller}#destroy"
end
```

```ruby
router.draw do
  resources :posts
  resources :users
end

# Now you have 14 routes registered!
```

This is what Rails does — `resources` is just a method that calls `get`, `post`, etc. multiple times.

---

## Exercises

1. Add a `put` method to the router (same as `patch`).
2. Add route constraints: `get "/posts/:id", to: "posts#show", constraints: { id: /\d+/ }` — only match if `:id` is digits.
3. Implement **nested routes**: `resources :posts do; resources :comments; end` — generates `/posts/:post_id/comments`, etc.
4. Add a `root` helper: `root to: "home#index"` should register `GET /`.
5. Print all registered routes in a table format (like `rails routes`).

---

## What You Learned

| Concept | What it does |
|---------|-------------|
| HTTP method + path | uniquely identifies a request type |
| Rack | the universal Ruby web interface: `call(env)` → `[status, headers, body]` |
| `instance_eval` | run a block in the context of another object (DSL magic) |
| Named regex captures | `(?<id>[^/]+)` extracts URL params cleanly |
| `resources` | just a method that registers 7 routes at once |
