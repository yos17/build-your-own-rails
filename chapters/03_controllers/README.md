# Chapter 3 — Controllers: Handling Requests

## What Does a Controller Do?

A controller sits between the router and the view. Its job:
1. Receive the request (with params)
2. Talk to the model (fetch/save data)
3. Render a response (HTML, JSON, redirect)

In Rails:
```ruby
class PostsController < ApplicationController
  def index
    @posts = Post.all
    render :index   # renders views/posts/index.html.erb
  end

  def show
    @post = Post.find(params[:id])
    render :show
  end
end
```

Everything in there — `params`, `render`, `redirect_to` — is provided by `ApplicationController`. Let's build all of it.

---

## The Request Object

First, let's wrap the raw Rack `env` hash in a friendly object:

```ruby
# framework/lib/tracks/request.rb

module Tracks
  class Request
    attr_reader :env, :params, :method, :path

    def initialize(env)
      @env    = env
      @method = env["REQUEST_METHOD"]
      @path   = env["PATH_INFO"]
      @params = parse_params
    end

    def get?;    @method == "GET";    end
    def post?;   @method == "POST";   end
    def patch?;  @method == "PATCH";  end
    def delete?; @method == "DELETE"; end

    def body
      @body ||= @env["rack.input"]&.read
    end

    private

    def parse_params
      params = {}

      # Query string: /posts?page=2&sort=asc
      query = @env["QUERY_STRING"] || ""
      query.split("&").each do |pair|
        key, value = pair.split("=", 2)
        params[key] = URI.decode_www_form_component(value.to_s) if key
      end

      # POST body: form data
      if @method == "POST" || @method == "PATCH"
        (body || "").split("&").each do |pair|
          key, value = pair.split("=", 2)
          params[key] = URI.decode_www_form_component(value.to_s) if key
        end
      end

      params
    end
  end
end
```

---

## The Response Object

```ruby
# framework/lib/tracks/response.rb

module Tracks
  class Response
    attr_accessor :status, :headers, :body

    def initialize
      @status  = 200
      @headers = { "Content-Type" => "text/html" }
      @body    = []
    end

    def write(text)
      @body << text.to_s
    end

    def redirect_to(url, status: 302)
      @status  = status
      @headers["Location"] = url
      @body = []
    end

    def to_rack
      [@status, @headers, @body]
    end
  end
end
```

---

## The Base Controller

This is the heart. Every controller in your app inherits from this:

```ruby
# framework/lib/tracks/base_controller.rb

module Tracks
  class BaseController
    attr_reader :request, :response, :params

    def initialize(request, response)
      @request  = request
      @response = response
      @params   = request.params
    end

    # --- Rendering ---

    def render(template_name, locals: {})
      # Figure out which file to render
      # e.g., PostsController#index → views/posts/index.html.erb
      controller_name = self.class.name
        .gsub("Controller", "")
        .gsub("::", "/")
        .downcase

      template_path = "app/views/#{controller_name}/#{template_name}.html.erb"

      # Render it and write to response
      content = Views::ERBTemplate.render(template_path, binding)
      response.write(content)
    end

    def render_json(data, status: 200)
      require 'json'
      response.status  = status
      response.headers["Content-Type"] = "application/json"
      response.write(data.to_json)
    end

    def render_text(text, status: 200)
      response.status = status
      response.write(text)
    end

    # --- Redirecting ---

    def redirect_to(url)
      response.redirect_to(url)
    end

    # --- Instance variables shared with views ---
    # When you do @posts = Post.all in a controller,
    # the view can access @posts because it renders
    # in the same binding (same context object).

    # --- Params helper ---
    def params
      # merge URL params (from router) + query/body params
      @params ||= {}
    end

    # --- Before actions ---
    def self.before_action(method_name, only: nil, except: nil)
      @before_actions ||= []
      @before_actions << { method: method_name, only: only, except: except }
    end

    def self.before_actions
      @before_actions || []
    end

    def run_before_actions(action_name)
      self.class.before_actions.each do |ba|
        next if ba[:only]   && !Array(ba[:only]).include?(action_name.to_sym)
        next if ba[:except] && Array(ba[:except]).include?(action_name.to_sym)
        send(ba[:method])
      end
    end
  end
end
```

---

## Dispatching to a Controller

Now we connect the router to the controllers. When a request comes in:

```ruby
# framework/lib/tracks/dispatcher.rb

module Tracks
  class Dispatcher
    def initialize(router)
      @router = router
    end

    def call(env)
      request  = Request.new(env)
      response = Response.new

      route, url_params = @router.route_for(request.method, request.path)

      if route.nil?
        response.status = 404
        response.write("404 Not Found: #{request.path}")
        return response.to_rack
      end

      # Merge URL params into request params
      request.params.merge!(url_params)

      # Find and instantiate the controller class
      # "posts" → PostsController
      controller_class = Object.const_get("#{route.controller.capitalize}Controller")
      controller = controller_class.new(request, response)

      # Run before actions
      controller.run_before_actions(route.action)

      # Call the action method
      controller.send(route.action)

      response.to_rack

    rescue => e
      response.status = 500
      response.write("500 Internal Server Error: #{e.message}")
      response.write("<pre>#{e.backtrace.join("\n")}</pre>")
      response.to_rack
    end
  end
end
```

The key line:
```ruby
controller.send(route.action)
```

`send` calls a method by name. If the action is `"show"`, this calls `controller.show`. This is how Rails dispatches to controller actions.

---

## Writing a Controller in Your App

Now you can write controllers that feel like Rails:

```ruby
# app/controllers/posts_controller.rb

class PostsController < Tracks::BaseController
  before_action :require_login, only: [:create, :edit, :update, :destroy]

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
      title: params["post[title]"],
      body:  params["post[body]"]
    )

    if @post.save
      redirect_to "/posts/#{@post.id}"
    else
      render :new
    end
  end

  private

  def require_login
    unless session[:user_id]
      redirect_to "/login"
    end
  end
end
```

This looks exactly like real Rails. Because the concepts are identical — `render`, `redirect_to`, `before_action`, `params`. We just built them ourselves.

---

## The `binding` Trick

You noticed `render` passes `binding` to the template:

```ruby
content = Views::ERBTemplate.render(template_path, binding)
```

`binding` is a Ruby object that captures the **current execution context** — all local variables, instance variables, and methods available right now.

By passing the controller's binding to ERB, the template can access `@posts`, `@post`, etc. — the instance variables you set in the controller action.

This is exactly what Rails does. When you set `@posts = Post.all` in a controller and use `@posts` in the view, it works because the view is evaluated in the controller's binding.

---

## `before_action` — How It Works

```ruby
def self.before_action(method_name, only: nil, except: nil)
  @before_actions ||= []
  @before_actions << { method: method_name, only: only, except: except }
end
```

`before_action` is a **class method** (defined with `self.`). When you write:

```ruby
class PostsController < Tracks::BaseController
  before_action :require_login, only: [:create]
end
```

Ruby calls `PostsController.before_action(:require_login, only: [:create])`.

This stores it in a class-level array `@before_actions`. Later, when an action runs, we check this array and call any matching before actions first.

Notice `@before_actions ||= []` — the `||=` means "set to empty array if it's nil". This is a Ruby idiom for lazy initialization.

---

## Exercises

1. Add `after_action` — runs after the action, before the response is sent.
2. Add `render_nothing(status: 204)` for actions that don't return a body.
3. Add `head :ok` — send just a status code, no body.
4. Make `params` support nested params like `params[:post][:title]` (hint: parse `post[title]` keys into nested hashes).
5. Add a `flash` hash — a message that survives exactly one redirect (like Rails flash).

---

## Solutions

### Exercise 1 — `after_action`

```ruby
# framework/lib/tracks/base_controller.rb — add after_action support

module Tracks
  class BaseController
    # --- After actions ---

    def self.after_action(method_name, only: nil, except: nil)
      @after_actions ||= []
      @after_actions << {
        method: method_name,
        only:   Array(only).map(&:to_sym),
        except: Array(except).map(&:to_sym)
      }
    end

    def self.after_actions
      @after_actions || []
    end

    def run_after_actions(action_name)
      self.class.after_actions.each do |aa|
        next if aa[:only].any?   && !aa[:only].include?(action_name.to_sym)
        next if aa[:except].any? &&  aa[:except].include?(action_name.to_sym)
        send(aa[:method])
      end
    end
  end
end

# In framework/lib/tracks/dispatcher.rb, update the dispatch to call after_actions:
#
#   controller.run_before_actions(route.action)
#   controller.send(route.action)
#   controller.run_after_actions(route.action)   # <-- add this line
#   response.to_rack

# Usage in an app controller:
# File: app/controllers/posts_controller.rb
class PostsController < Tracks::BaseController
  after_action :log_action
  after_action :track_analytics, only: [:show, :index]

  def index
    @posts = Post.all
    render :index
  end

  private

  def log_action
    puts "[PostsController] Action completed at #{Time.now}"
  end

  def track_analytics
    # Could write to an analytics table, etc.
    puts "[Analytics] Page viewed: #{request.path}"
  end
end
```

### Exercise 2 — `render_nothing(status: 204)`

```ruby
# framework/lib/tracks/base_controller.rb — add render_nothing

module Tracks
  class BaseController
    def render_nothing(status: 204)
      response.status = status
      response.headers["Content-Length"] = "0"
      # body stays empty — no response.write call
    end
  end
end

# Usage:
# File: app/controllers/likes_controller.rb
class LikesController < Tracks::BaseController
  def create
    post = Post.find(params["post_id"])
    Like.create(post_id: post.id, user_id: session[:user_id])
    render_nothing(status: 204)   # 204 No Content — AJAX-friendly
  end

  def destroy
    Like.find(params["id"]).destroy
    render_nothing   # defaults to 204
  end
end
```

### Exercise 3 — `head :ok`

```ruby
# framework/lib/tracks/base_controller.rb — add head helper

module Tracks
  class BaseController
    STATUS_CODES = {
      ok:                  200,
      created:             201,
      accepted:            202,
      no_content:          204,
      moved_permanently:   301,
      found:               302,
      not_modified:        304,
      bad_request:         400,
      unauthorized:        401,
      forbidden:           403,
      not_found:           404,
      unprocessable_entity: 422,
      internal_server_error: 500
    }.freeze

    def head(status_symbol, headers: {})
      code = STATUS_CODES.fetch(status_symbol, status_symbol)
      response.status = code
      headers.each { |k, v| response.headers[k.to_s] = v }
      # no body written
    end
  end
end

# Usage:
# File: app/controllers/api/posts_controller.rb
class Api::PostsController < Tracks::BaseController
  def create
    post = Post.new(title: params["title"], body: params["body"])
    if post.save
      head :created, headers: { "Location" => "/api/posts/#{post.id}" }
    else
      render_json({ errors: post.errors }, status: 422)
    end
  end

  def update
    post = Post.find(params["id"])
    post.title = params["title"]
    post.save
    head :ok
  end
end
```

### Exercise 4 — Nested params (`params[:post][:title]`)

```ruby
# framework/lib/tracks/request.rb — update parse_params to build nested hashes

module Tracks
  class Request
    private

    def parse_params
      params = {}

      query = @env["QUERY_STRING"] || ""
      parse_encoded_string(query, params)

      if ["POST", "PATCH", "PUT"].include?(@method)
        parse_encoded_string(body.to_s, params)
      end

      params
    end

    # Parse "post[title]=Hello&post[body]=World" into
    # { "post" => { "title" => "Hello", "body" => "World" } }
    def parse_encoded_string(str, params)
      str.split("&").each do |pair|
        raw_key, raw_value = pair.split("=", 2)
        next unless raw_key

        key   = URI.decode_www_form_component(raw_key)
        value = URI.decode_www_form_component(raw_value.to_s)

        assign_nested_param(params, key, value)
      end
      params
    end

    # "post[title]" → params["post"]["title"] = value
    # "tags[]"      → params["tags"] = [..., value]
    # "name"        → params["name"] = value
    def assign_nested_param(hash, key, value)
      if key.include?("[")
        root, rest = key.split("[", 2)
        rest = rest.chomp("]")

        if rest.empty?
          # Array param: tags[]
          hash[root] ||= []
          hash[root] << value
        else
          # Nested hash: post[title]
          hash[root] ||= {}
          # Recurse for deeper nesting: post[meta][keywords]
          if rest.include?("[")
            inner_key = rest
            assign_nested_param(hash[root], inner_key, value)
          else
            hash[root][rest] = value
          end
        end
      else
        hash[key] = value
      end
    end
  end
end

# Usage in a controller — params now supports nested access:
# File: app/controllers/posts_controller.rb
class PostsController < Tracks::BaseController
  def create
    # Form sends: post[title]=Hello&post[body]=World
    post_params = params["post"]   # => { "title" => "Hello", "body" => "World" }

    @post = Post.new(
      title: post_params["title"],
      body:  post_params["body"],
      user_id: session[:user_id]
    )

    if @post.save
      redirect_to "/posts/#{@post.id}"
    else
      render :new
    end
  end
end
```

### Exercise 5 — Flash messages

```ruby
# framework/lib/tracks/base_controller.rb — add flash support

module Tracks
  class BaseController
    # Flash: survives exactly one redirect, then is cleared
    def flash
      @flash ||= Flash.new(session)
    end

    class Flash
      def initialize(session)
        @session = session
        @session[:flash] ||= {}
        @session[:flash_used] ||= []
      end

      def []=(key, value)
        @session[:flash][key.to_s] = value
      end

      def [](key)
        @session[:flash][key.to_s]
      end

      def any?
        !@session[:flash].empty?
      end

      # Call this at the start of each request to sweep used flash entries
      def sweep!
        @session[:flash_used].each { |k| @session[:flash].delete(k) }
        @session[:flash_used] = @session[:flash].keys
      end
    end
  end
end

# In framework/lib/tracks/dispatcher.rb, sweep flash before each action:
#
#   controller = controller_class.new(request, response)
#   controller.flash.sweep!   # <-- add this line
#   controller.run_before_actions(route.action)
#   controller.send(route.action)

# Usage in app controllers:
# File: app/controllers/posts_controller.rb
class PostsController < Tracks::BaseController
  def create
    @post = Post.new(title: params["post[title]"], body: params["post[body]"])
    if @post.save
      flash[:notice] = "Post created successfully!"
      redirect_to "/posts/#{@post.id}"
    else
      flash[:error] = "Could not create post."
      render :new
    end
  end

  def destroy
    Post.find(params["id"]).destroy
    flash[:notice] = "Post deleted."
    redirect_to "/posts"
  end
end

# In your layout (app/views/layouts/application.html.erb):
# <% if flash[:notice] %>
#   <div class="flash notice"><%= flash[:notice] %></div>
# <% end %>
# <% if flash[:error] %>
#   <div class="flash error"><%= flash[:error] %></div>
# <% end %>
```

---

## What You Learned

| Concept | Key point |
|---------|-----------|
| Request object | wraps Rack `env`, parses params |
| Response object | builds Rack response `[status, headers, body]` |
| `send` | dispatches to controller action by name |
| `binding` | captures current context — how views see controller variables |
| `before_action` | a class method that stores callbacks; checked before each action |
| `||=` | Ruby idiom: initialize if nil |
| Inheritance | `class PostsController < BaseController` gets all base methods |
