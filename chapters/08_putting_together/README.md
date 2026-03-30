# Chapter 8 — Putting It All Together

## You've Built a Web Framework

Let's review what we have:

```
framework/lib/tracks/
  router.rb         — maps URLs to controller#action
  dispatcher.rb     — finds controller, calls action
  request.rb        — wraps Rack env, parses params
  response.rb       — builds [status, headers, body]
  base_controller.rb — render, redirect, params, before_action
  erb_template.rb   — renders ERB views with layouts
  model.rb          — ORM: find, all, where, save, destroy
  associations.rb   — belongs_to, has_many
  validations.rb    — validates :field, presence: true
  query.rb          — chainable query builder
  migrator.rb       — runs migration files
  middleware/
    logger.rb       — logs requests
    session.rb      — cookies and session storage
    static.rb       — serves files from /public
    csrf.rb         — CSRF protection
  middleware_stack.rb — builds the middleware chain
  application.rb    — the entry point, wires everything
```

Now let's build a **real app** on top of it.

---

## The App: A Simple Blog

```
GET  /              → HomeController#index
GET  /posts         → PostsController#index
GET  /posts/:id     → PostsController#show
GET  /posts/new     → PostsController#new
POST /posts         → PostsController#create
GET  /posts/:id/edit → PostsController#edit
PATCH /posts/:id    → PostsController#update
DELETE /posts/:id   → PostsController#destroy
GET  /login         → SessionsController#new
POST /login         → SessionsController#create
DELETE /logout      → SessionsController#destroy
```

---

## The Entry Point

```ruby
# config.ru  (Rack's config file)

require_relative "framework/lib/tracks"

# Load the app
Dir["app/models/*.rb"].each    { |f| require_relative f }
Dir["app/controllers/*.rb"].each { |f| require_relative f }

# Define the app
class App < Tracks::Application
  routes do
    root to: "home#index"
    resources :posts
    get  "/login",  to: "sessions#new"
    post "/login",  to: "sessions#create"
    delete "/logout", to: "sessions#destroy"
  end
end

run App.new
```

---

## Models

```ruby
# app/models/user.rb
class User < Tracks::Model
  include Tracks::Validations
  include Tracks::Associations

  has_many :posts

  validates :name,  presence: true
  validates :email, presence: true, uniqueness: true

  def authenticate(password)
    # In real Rails: BCrypt. Here: simple comparison.
    @attributes["password_digest"] == password
  end
end

# app/models/post.rb
class Post < Tracks::Model
  include Tracks::Validations
  include Tracks::Associations

  belongs_to :user

  validates :title, presence: true, length: { min: 3, max: 100 }
  validates :body,  presence: true

  def author_name
    user.name
  rescue
    "Unknown"
  end
end
```

---

## Controllers

```ruby
# app/controllers/posts_controller.rb
class PostsController < Tracks::BaseController
  before_action :require_login, only: [:new, :create, :edit, :update, :destroy]

  def index
    @posts = Post.all
    render :index
  end

  def show
    @post = Post.find(params["id"])
    render :show
  end

  def new
    @post = Post.new
    render :new
  end

  def create
    @post = Post.new(
      title:   params["post[title]"],
      body:    params["post[body]"],
      user_id: session[:user_id]
    )

    if @post.save
      redirect_to "/posts/#{@post.id}"
    else
      render :new
    end
  end

  def edit
    @post = Post.find(params["id"])
    render :edit
  end

  def update
    @post = Post.find(params["id"])
    @post.title = params["post[title]"]
    @post.body  = params["post[body]"]

    if @post.save
      redirect_to "/posts/#{@post.id}"
    else
      render :edit
    end
  end

  def destroy
    @post = Post.find(params["id"])
    @post.destroy
    redirect_to "/posts"
  end

  private

  def require_login
    unless session[:user_id]
      redirect_to "/login"
    end
  end
end

# app/controllers/sessions_controller.rb
class SessionsController < Tracks::BaseController
  def new
    render :new
  end

  def create
    user = User.find_by(email: params["email"])
    if user&.authenticate(params["password"])
      session[:user_id] = user.id
      redirect_to "/posts"
    else
      @error = "Invalid email or password"
      render :new
    end
  end

  def destroy
    session.delete(:user_id)
    redirect_to "/login"
  end
end
```

---

## Views

```erb
<!-- app/views/layouts/application.html.erb -->
<!DOCTYPE html>
<html>
<head>
  <title>Tracks Blog</title>
  <style>
    body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
    nav a { margin-right: 10px; }
    .error { color: red; }
    .post { border-bottom: 1px solid #eee; padding: 20px 0; }
  </style>
</head>
<body>
  <nav>
    <a href="/">Home</a>
    <a href="/posts">Posts</a>
    <% if session[:user_id] %>
      <a href="/posts/new">New Post</a>
      <form action="/logout" method="post" style="display:inline">
        <input type="hidden" name="_method" value="DELETE">
        <button type="submit">Logout</button>
      </form>
    <% else %>
      <a href="/login">Login</a>
    <% end %>
  </nav>

  <hr>
  <%= @_content %>
</body>
</html>

<!-- app/views/posts/index.html.erb -->
<h1>Posts</h1>
<% if @posts.empty? %>
  <p>No posts yet. <a href="/posts/new">Write one!</a></p>
<% else %>
  <% @posts.each do |post| %>
    <div class="post">
      <h2><a href="/posts/<%= post.id %>"><%= h(post.title) %></a></h2>
      <p><%= h(truncate(post.body, length: 150)) %></p>
      <small>by <%= h(post.author_name) %></small>
    </div>
  <% end %>
<% end %>

<!-- app/views/posts/show.html.erb -->
<article>
  <h1><%= h(@post.title) %></h1>
  <p><em>by <%= h(@post.author_name) %></em></p>
  <div><%= @post.body %></div>
  <p>
    <%= link_to "Edit", "/posts/#{@post.id}/edit" %> |
    <%= link_to "Back", "/posts" %>
  </p>
</article>

<!-- app/views/posts/new.html.erb -->
<h1>New Post</h1>
<% if @post.errors.any? %>
  <div class="error">
    <% @post.errors.each do |field, messages| %>
      <p><%= field %>: <%= messages.join(", ") %></p>
    <% end %>
  </div>
<% end %>

<form action="/posts" method="post">
  <p>
    <label>Title<br>
    <input type="text" name="post[title]" value="<%= h(@post.title.to_s) %>">
    </label>
  </p>
  <p>
    <label>Body<br>
    <textarea name="post[body]" rows="10"><%= h(@post.body.to_s) %></textarea>
    </label>
  </p>
  <input type="submit" value="Create Post">
</form>
```

---

## Run It

```bash
# Install dependencies
gem install rack sqlite3

# Create the database
mkdir -p db
ruby -e "
  require 'sqlite3'
  db = SQLite3::Database.new('db/development.sqlite3')
  db.execute(\"CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT UNIQUE, password_digest TEXT)\")
  db.execute(\"CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, body TEXT, user_id INTEGER, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)\")
  db.execute(\"INSERT INTO users (name, email, password_digest) VALUES ('Yosia', 'yosia@example.com', 'password')\")
  puts 'Database ready!'
"

# Start the server
rackup config.ru -p 3000
```

Visit `http://localhost:3000`

---

## What You Just Built

A web framework with:
- ✅ URL routing with parameters
- ✅ Controllers with before_action
- ✅ ERB views with layouts, helpers, partials
- ✅ An ORM: find, all, where, save, destroy
- ✅ Associations: belongs_to, has_many
- ✅ Validations: presence, length, uniqueness
- ✅ Middleware: logging, sessions, CSRF, static files
- ✅ A working blog app

In ~600 lines of Ruby.

---

## How Rails Differs

Real Rails is the same concepts, but:

| Feature | Ours | Rails |
|---------|------|-------|
| ORM | ~100 lines | 10,000+ lines (ActiveRecord) |
| Router | ~60 lines | 5,000+ lines (ActionDispatch) |
| Views | ERB only | ERB + Haml + Slim + caching |
| Middleware | 4 | ~20 built-in |
| Database | SQLite only | Any (Postgres, MySQL, SQLite) |
| Associations | belongs_to, has_many | + has_one, has_many through, polymorphic |
| Validations | 3 types | 15+ types + custom |

Rails has had 20 years of edge cases handled. But the **architecture** is identical. When you read Rails source code now, you'll recognize the patterns.

---

## Where to Go Next

1. **Add PostgreSQL support** — replace SQLite3 gem with `pg`, adjust SQL syntax slightly
2. **Add authentication** — BCrypt for passwords, token auth for APIs
3. **Add JSON API** — `render_json` support in controllers, format detection
4. **Add ActiveJob-style background jobs** — async processing with a queue
5. **Read Rails source** — start with `actionpack/lib/action_dispatch/routing`
6. **Build a real app** — take what you built and make something useful

---

## The Final Lesson

Rails is not magic. It's Ruby.

Every piece of "magic" you've seen in Rails:
- `Post.find(5)` → class method + SQL
- `belongs_to :user` → `define_method` generating an instance method
- `validates :title` → class method storing rules in an array
- `before_action :login` → class method + `send` at dispatch time
- `render :index` → ERB + file path convention + `binding`
- `params[:id]` → parsed from URL + query string + request body

None of it is magic. It's metaprogramming, conventions, and composition.

Now you know.
