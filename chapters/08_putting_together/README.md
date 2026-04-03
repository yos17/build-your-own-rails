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

## Solutions

### Exercise 1 — Add PostgreSQL support

```ruby
# framework/lib/tracks/adapters/postgresql.rb
# Replace SQLite3 with the 'pg' gem for production-grade databases.

require 'pg'

module Tracks
  module Adapters
    class PostgreSQL
      attr_reader :connection

      def initialize(config = {})
        @config = {
          host:     ENV["DB_HOST"]     || "localhost",
          port:     (ENV["DB_PORT"]    || 5432).to_i,
          dbname:   ENV["DB_NAME"]     || "tracks_development",
          user:     ENV["DB_USER"]     || "postgres",
          password: ENV["DB_PASSWORD"] || ""
        }.merge(config)

        @connection = PG.connect(@config)
      end

      # Mimic SQLite3's execute interface so Model works unchanged
      def execute(sql, params = [])
        # PG uses $1, $2 placeholders; convert from ? style
        pg_sql = convert_placeholders(sql)
        result = @connection.exec_params(pg_sql, params)
        result.to_a   # Array of hashes (column name => value)
      end

      def last_insert_row_id
        @connection.exec("SELECT lastval()").first["lastval"].to_i
      end

      def results_as_hash=(val)
        # PG always returns hashes — nothing to do
      end

      private

      def convert_placeholders(sql)
        i = 0
        sql.gsub("?") { i += 1; "$#{i}" }
      end
    end
  end
end

# framework/lib/tracks/model.rb — swap in the adapter via environment variable

module Tracks
  class Model
    def self.db
      @@db ||= begin
        if ENV["DATABASE_ADAPTER"] == "postgresql"
          Adapters::PostgreSQL.new
        else
          db = SQLite3::Database.new(ENV["DATABASE_PATH"] || "db/development.sqlite3")
          db.results_as_hash = true
          db
        end
      end
    end
  end
end

# To use PostgreSQL, set environment variables before starting the server:
#   DATABASE_ADAPTER=postgresql
#   DB_HOST=localhost
#   DB_NAME=my_app_development
#   DB_USER=postgres
#   DB_PASSWORD=secret
#
# Then start normally:
#   DATABASE_ADAPTER=postgresql rackup config.ru -p 3000
```

### Exercise 2 — Add authentication (BCrypt passwords)

```ruby
# Gemfile — add bcrypt gem
# gem 'bcrypt'

# app/models/user.rb — BCrypt password hashing
require 'bcrypt'

class User < Tracks::Model
  validates :name,  presence: true
  validates :email, presence: true, uniqueness: true

  has_many :posts

  # Store hashed password; never store plaintext
  def password=(plaintext)
    @attributes["password_digest"] = BCrypt::Password.create(plaintext)
  end

  def authenticate(plaintext)
    digest = @attributes["password_digest"]
    return false if digest.nil? || digest.empty?
    BCrypt::Password.new(digest) == plaintext
  end
end

# app/controllers/sessions_controller.rb — login / logout
class SessionsController < Tracks::BaseController
  def new
    render :new
  end

  def create
    user = User.find_by(email: params["email"])

    if user&.authenticate(params["password"])
      session[:user_id] = user.id
      flash[:notice] = "Welcome back, #{user.name}!"
      redirect_to "/posts"
    else
      @error = "Invalid email or password."
      render :new
    end
  end

  def destroy
    session.delete(:user_id)
    flash[:notice] = "Logged out."
    redirect_to "/login"
  end
end

# app/controllers/application_controller.rb — shared auth helpers
class ApplicationController < Tracks::BaseController
  def current_user
    return nil unless session[:user_id]
    @current_user ||= User.find(session[:user_id])
  rescue
    nil
  end

  def logged_in?
    !!current_user
  end

  def require_login
    unless logged_in?
      flash[:error] = "You must be logged in."
      redirect_to "/login"
    end
  end
end

# All other controllers inherit from ApplicationController:
class PostsController < ApplicationController
  before_action :require_login, only: [:new, :create, :edit, :update, :destroy]
  # ...
end
```

### Exercise 3 — JSON API support

```ruby
# framework/lib/tracks/base_controller.rb — add format detection

module Tracks
  class BaseController
    def request_format
      content_type = @request.env["CONTENT_TYPE"] || ""
      accept       = @request.env["HTTP_ACCEPT"]  || ""
      path         = @request.path

      if path.end_with?(".json") || accept.include?("application/json") ||
         content_type.include?("application/json")
        :json
      else
        :html
      end
    end

    def json_request?
      request_format == :json
    end

    # Respond to different formats in one action:
    def respond_to
      yield FormatResponder.new(self)
    end

    class FormatResponder
      def initialize(controller)
        @controller = controller
        @format     = controller.request_format
      end

      def html(&block)
        block.call if @format == :html
      end

      def json(&block)
        block.call if @format == :json
      end
    end
  end
end

# Usage in a controller action:
# File: app/controllers/posts_controller.rb
class PostsController < ApplicationController
  def index
    @posts = Post.all

    respond_to do |format|
      format.html { render :index }
      format.json { render_json(@posts.map(&:to_h)) }
    end
  end

  def show
    @post = Post.find(params["id"])

    respond_to do |format|
      format.html { render :show }
      format.json { render_json(@post.to_h) }
    end
  end

  def create
    @post = Post.new(
      title:   params["title"] || params.dig("post", "title"),
      body:    params["body"]  || params.dig("post", "body"),
      user_id: session[:user_id]
    )

    if @post.save
      respond_to do |format|
        format.html { redirect_to "/posts/#{@post.id}" }
        format.json { render_json(@post.to_h, status: 201) }
      end
    else
      respond_to do |format|
        format.html { render :new }
        format.json { render_json({ errors: @post.errors }, status: 422) }
      end
    end
  end
end

# Example JSON API calls:
#   curl http://localhost:3000/posts.json
#   curl http://localhost:3000/posts -H "Accept: application/json"
#   curl -X POST http://localhost:3000/posts \
#        -H "Content-Type: application/json" \
#        -d '{"title":"Hello","body":"World"}'
```

### Exercise 4 — Background jobs

```ruby
# framework/lib/tracks/job.rb — simple background job system

require 'json'

module Tracks
  class Job
    @@queue = []
    @@mutex = Mutex.new

    # DSL: class method to enqueue
    def self.perform_later(*args)
      @@mutex.synchronize do
        @@queue << { job: name, args: args, enqueued_at: Time.now.to_f }
      end
      puts "[Job] Enqueued #{name} with args: #{args.inspect}"
    end

    # Process all pending jobs (call from a background thread or worker process)
    def self.drain_queue!
      @@mutex.synchronize do
        jobs = @@queue.dup
        @@queue.clear
        jobs
      end.each do |job_data|
        klass = Object.const_get(job_data[:job])
        klass.new.perform(*job_data[:args])
      end
    end

    # Subclasses implement perform:
    def perform(*args)
      raise NotImplementedError, "#{self.class}#perform must be implemented"
    end
  end
end

# Start a worker thread in config.ru:
#   Thread.new do
#     loop do
#       Tracks::Job.drain_queue!
#       sleep 1
#     end
#   end

# Usage — define specific jobs:
# File: app/jobs/welcome_email_job.rb
class WelcomeEmailJob < Tracks::Job
  def perform(user_id)
    user = User.find(user_id)
    # In a real app, send email via SMTP / SendGrid / etc.
    puts "[WelcomeEmailJob] Sending welcome email to #{user.email}"
    # Mail.deliver(to: user.email, subject: "Welcome!", body: "...")
  end
end

# File: app/jobs/post_notification_job.rb
class PostNotificationJob < Tracks::Job
  def perform(post_id)
    post = Post.find(post_id)
    puts "[PostNotificationJob] Notifying followers about post ##{post_id}: #{post.title}"
  end
end

# In a controller — enqueue without blocking the HTTP response:
# File: app/controllers/users_controller.rb
class UsersController < ApplicationController
  def create
    @user = User.new(name: params["name"], email: params["email"])
    @user.password = params["password"]

    if @user.save
      WelcomeEmailJob.perform_later(@user.id)   # runs in background
      redirect_to "/posts"
    else
      render :new
    end
  end
end

class PostsController < ApplicationController
  def create
    @post = Post.new(title: params["post[title]"], body: params["post[body]"], user_id: session[:user_id])
    if @post.save
      PostNotificationJob.perform_later(@post.id)  # async
      redirect_to "/posts/#{@post.id}"
    else
      render :new
    end
  end
end
```

### Exercise 5 — Read Rails source (guided tour)

```ruby
# This exercise is exploratory. Here are the key Rails files that mirror
# what we built, and what to look for in each one.

# 1. ROUTING — actionpack/lib/action_dispatch/routing/
#
#    mapper.rb          — defines get/post/resources/scope etc (like our Router#draw)
#    route_set.rb       — the RouteSet class, stores all routes (like our @routes array)
#    pattern.rb         — converts "/posts/:id" to a regex (like our Router#match)
#
#    Key similarity: Rails' get/post/resources are methods on a Mapper object,
#    and routes.draw runs the block with instance_eval — exactly like us.

# 2. CONTROLLERS — actionpack/lib/action_controller/
#
#    base.rb            — ActionController::Base (like our BaseController)
#    metal.rb           — the Rack interface layer
#    rendering.rb       — render method (like our BaseController#render)
#    redirecting.rb     — redirect_to (like our #redirect_to)
#    before_action.rb   — callbacks (like our before_action)
#    params_wrapper.rb  — nested params parsing (like our Exercise 4 in Ch 3)
#
#    Key similarity: Rails controllers use the same `send(action)` dispatch
#    and binding tricks for views.

# 3. MODELS — activerecord/lib/active_record/
#
#    base.rb            — ActiveRecord::Base (like our Model)
#    relation.rb        — the Query object (like our Query class)
#    associations/      — belongs_to, has_many (like our Associations module)
#    validations/       — validates :field, rules (like our Validations module)
#    callbacks.rb       — before_save, after_create (like our Ch 5 exercises)
#    connection_adapters/— PostgreSQL/SQLite adapters (like our Ch 8 Exercise 1)
#
#    Key similarity: ActiveRecord::Relation (the query object) returns `self`
#    for chaining, executes SQL lazily — exactly like our Query class.

# 4. MIDDLEWARE — railties/lib/rails/application/
#
#    default_middleware_stack.rb — lists ~20 default middleware
#
#    actionpack/lib/action_dispatch/middleware/
#      flash.rb         — flash messages (like our Ch 7 Exercise 4)
#      session/         — cookie and database session stores
#      request_id.rb    — X-Request-ID (like our Ch 7 Exercise 3)
#      logger.rb        — request logging (like our Logger middleware)

# Quick way to see Rails' middleware stack for a real app:
#   cd my_rails_app
#   rails middleware
#
# You'll recognize: Rack::Sendfile, ActionDispatch::Static, Rack::MethodOverride,
# ActionDispatch::RequestId, ActionDispatch::RemoteIp, ActionDispatch::Session::CookieStore,
# ActionDispatch::Flash... all the same concepts we built.
```

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
