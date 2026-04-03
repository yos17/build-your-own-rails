# Chapter 7 — Middleware: The Request Pipeline

## What is Middleware?

Imagine the request/response cycle as a pipe. Your app is at the end. **Middleware** are components you insert into the pipe — each one can inspect, modify, or short-circuit the request/response.

```
Request → Logger → Session → Auth → Your App → Response
                                        ↕
                             (your controller runs here)
```

Each middleware:
1. Receives the request (and the next app in the chain)
2. Can do something before (logging, auth check, parse cookies)
3. Calls the next app
4. Can do something after (add headers, compress response)

This is called the **middleware stack** in Rails. Rails itself ships with ~20 middleware (session, CSRF protection, logging, static file serving, etc.).

---

## Rack Middleware Contract

Any Rack middleware is an object with:
- An `initialize(app)` that stores the next app
- A `call(env)` that processes the request

```ruby
class MyMiddleware
  def initialize(app)
    @app = app    # the next layer
  end

  def call(env)
    # Do something BEFORE
    puts "Request coming in: #{env['PATH_INFO']}"

    # Call the next layer (could be another middleware or your app)
    status, headers, body = @app.call(env)

    # Do something AFTER
    puts "Response going out: #{status}"

    # Return the (possibly modified) response
    [status, headers, body]
  end
end
```

To stack them:
```ruby
app = MyApp.new
app = AuthMiddleware.new(app)
app = LoggerMiddleware.new(app)
app = SessionMiddleware.new(app)
# Now requests go through Session → Auth → Logger → MyApp
```

---

## Building a Logger Middleware

```ruby
# framework/lib/tracks/middleware/logger.rb

module Tracks
  module Middleware
    class Logger
      def initialize(app)
        @app = app
      end

      def call(env)
        start_time = Time.now
        method = env["REQUEST_METHOD"]
        path   = env["PATH_INFO"]

        status, headers, body = @app.call(env)

        duration = ((Time.now - start_time) * 1000).round(1)
        color    = color_for_status(status)

        puts "#{color}#{method} #{path} → #{status} (#{duration}ms)\e[0m"

        [status, headers, body]
      end

      private

      def color_for_status(status)
        case status
        when 200..299 then "\e[32m"   # green
        when 300..399 then "\e[34m"   # blue
        when 400..499 then "\e[33m"   # yellow
        when 500..599 then "\e[31m"   # red
        else "\e[0m"
        end
      end
    end
  end
end
```

---

## Building a Session Middleware

Sessions store data between requests. HTTP is stateless — each request knows nothing about previous ones. Sessions solve this using cookies.

How it works:
1. First request: generate a session ID, store it in a cookie
2. Server stores session data in memory (or database) keyed by that ID
3. Next request: read cookie, look up session data

```ruby
# framework/lib/tracks/middleware/session.rb

require 'securerandom'
require 'json'

module Tracks
  module Middleware
    class Session
      SESSION_KEY = "_tracks_session"
      @@sessions = {}   # In-memory store — use Redis in production

      def initialize(app)
        @app = app
      end

      def call(env)
        # Parse session ID from cookies
        session_id = parse_cookie(env, SESSION_KEY)

        # Create new session if needed
        session_id ||= SecureRandom.hex(32)
        @@sessions[session_id] ||= {}

        # Make session available to the app
        env["tracks.session"]    = @@sessions[session_id]
        env["tracks.session_id"] = session_id

        status, headers, body = @app.call(env)

        # Set the session cookie in the response
        headers["Set-Cookie"] = "#{SESSION_KEY}=#{session_id}; HttpOnly; Path=/"

        [status, headers, body]
      end

      private

      def parse_cookie(env, key)
        cookie_header = env["HTTP_COOKIE"] || ""
        cookies = cookie_header.split("; ").each_with_object({}) do |pair, h|
          k, v = pair.split("=", 2)
          h[k] = v
        end
        cookies[key]
      end
    end
  end
end
```

Now in the controller, we can access the session:
```ruby
class BaseController
  def session
    @request.env["tracks.session"]
  end
end

# In a controller action:
def login
  user = User.find_by(email: params["email"])
  if user&.authenticate(params["password"])
    session[:user_id] = user.id
    redirect_to "/dashboard"
  end
end
```

---

## Building a Static Files Middleware

Serve CSS, JS, images without hitting the app:

```ruby
module Tracks
  module Middleware
    class Static
      STATIC_DIR = "public"
      MIME_TYPES = {
        ".html" => "text/html",
        ".css"  => "text/css",
        ".js"   => "application/javascript",
        ".png"  => "image/png",
        ".jpg"  => "image/jpeg",
        ".svg"  => "image/svg+xml",
        ".ico"  => "image/x-icon"
      }

      def initialize(app)
        @app = app
      end

      def call(env)
        path = env["PATH_INFO"]
        file_path = File.join(STATIC_DIR, path)

        if File.file?(file_path)
          ext      = File.extname(file_path)
          content  = File.read(file_path)
          mime     = MIME_TYPES[ext] || "application/octet-stream"
          return [200, {"Content-Type" => mime}, [content]]
        end

        @app.call(env)
      end
    end
  end
end
```

---

## The Middleware Stack Builder

```ruby
# framework/lib/tracks/middleware_stack.rb

module Tracks
  class MiddlewareStack
    def initialize
      @middlewares = []
    end

    def use(middleware_class, *args)
      @middlewares << [middleware_class, args]
    end

    def build(app)
      # Build the stack from inside out
      # Last added = outermost (first to process request)
      @middlewares.reverse.reduce(app) do |inner, (klass, args)|
        klass.new(inner, *args)
      end
    end
  end
end
```

---

## The Application Class — Tying It All Together

```ruby
# framework/lib/tracks/application.rb

module Tracks
  class Application
    attr_reader :router

    def initialize
      @router = Router.new
      @middleware = MiddlewareStack.new

      # Default middleware
      @middleware.use(Middleware::Static)
      @middleware.use(Middleware::Logger)
      @middleware.use(Middleware::Session)
    end

    def use(middleware, *args)
      @middleware.use(middleware, *args)
    end

    def routes(&block)
      @router.draw(&block)
    end

    def call(env)
      # Build the full stack and call it
      dispatcher = Dispatcher.new(@router)
      stack = @middleware.build(dispatcher)
      stack.call(env)
    end
  end
end
```

---

## CSRF Protection Middleware

Cross-Site Request Forgery — a form on an evil website silently submits to your app. Protection: include a secret token in every form; reject requests without it.

```ruby
module Tracks
  module Middleware
    class CSRF
      def initialize(app)
        @app = app
      end

      def call(env)
        session = env["tracks.session"] || {}

        # Generate token if none exists
        session[:csrf_token] ||= SecureRandom.hex(32)
        env["tracks.csrf_token"] = session[:csrf_token]

        # Check token on state-changing requests
        if %w[POST PATCH PUT DELETE].include?(env["REQUEST_METHOD"])
          req    = Rack::Request.new(env)
          token  = req.params["_csrf_token"]
          unless token && token == session[:csrf_token]
            return [403, {"Content-Type" => "text/html"}, ["CSRF token mismatch"]]
          end
        end

        @app.call(env)
      end
    end
  end
end
```

Then include the token in every form:
```erb
<form action="/posts" method="post">
  <input type="hidden" name="_csrf_token" value="<%= csrf_token %>">
  <!-- rest of form -->
</form>
```

---

## Exercises

1. Build a **rate limiter** middleware: block IPs that make more than 100 requests/minute.
2. Build a **compression middleware** that gzip-compresses responses larger than 1KB.
3. Build a **request ID middleware** that adds a unique `X-Request-ID` header to every request (useful for log tracing).
4. Add **flash messages** to the session middleware: values that survive exactly one request.
5. Build a **BasicAuth middleware**: `use Middleware::BasicAuth, username: "admin", password: "secret"`.

---

## Solutions

### Exercise 1 — Rate limiter middleware

```ruby
# framework/lib/tracks/middleware/rate_limiter.rb

module Tracks
  module Middleware
    class RateLimiter
      # Block IPs that make more than `max_requests` requests per `window` seconds.
      def initialize(app, max_requests: 100, window: 60)
        @app          = app
        @max_requests = max_requests
        @window       = window
        @requests     = {}   # { ip => [timestamp, timestamp, ...] }
        @mutex        = Mutex.new
      end

      def call(env)
        ip = env["REMOTE_ADDR"] || "unknown"

        if rate_limited?(ip)
          return [
            429,
            { "Content-Type" => "text/plain", "Retry-After" => @window.to_s },
            ["Too Many Requests — slow down!"]
          ]
        end

        @app.call(env)
      end

      private

      def rate_limited?(ip)
        now = Time.now.to_f

        @mutex.synchronize do
          # Remove timestamps outside the current window
          @requests[ip] ||= []
          @requests[ip].reject! { |t| t < now - @window }

          if @requests[ip].size >= @max_requests
            true   # rate limited
          else
            @requests[ip] << now
            false
          end
        end
      end
    end
  end
end

# Register in your Tracks::Application (framework/lib/tracks/application.rb):
#
#   @middleware.use(Middleware::RateLimiter, max_requests: 100, window: 60)
#
# Or in config.ru:
#
#   class App < Tracks::Application
#     use Tracks::Middleware::RateLimiter, max_requests: 50, window: 60
#   end
```

### Exercise 2 — Compression middleware (gzip)

```ruby
# framework/lib/tracks/middleware/compressor.rb

require 'zlib'
require 'stringio'

module Tracks
  module Middleware
    class Compressor
      MIN_SIZE = 1024   # Only compress responses larger than 1KB

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)

        # Only compress if client accepts gzip
        accept_encoding = env["HTTP_ACCEPT_ENCODING"] || ""
        return [status, headers, body] unless accept_encoding.include?("gzip")

        # Collect body content
        content = body.reduce("") { |s, chunk| s + chunk }
        return [status, headers, [content]] if content.bytesize < MIN_SIZE

        # Compress the content
        compressed = gzip(content)

        headers["Content-Encoding"] = "gzip"
        headers["Content-Length"]   = compressed.bytesize.to_s
        headers.delete("Content-Length") if headers["Transfer-Encoding"] == "chunked"

        [status, headers, [compressed]]
      end

      private

      def gzip(content)
        output = StringIO.new
        gz = Zlib::GzipWriter.new(output)
        gz.write(content)
        gz.close
        output.string
      end
    end
  end
end

# Register in your app:
#   use Tracks::Middleware::Compressor
#
# The middleware checks the Accept-Encoding header — curl example:
#   curl -H "Accept-Encoding: gzip" http://localhost:3000/posts
```

### Exercise 3 — Request ID middleware

```ruby
# framework/lib/tracks/middleware/request_id.rb

require 'securerandom'

module Tracks
  module Middleware
    class RequestId
      HEADER = "X-Request-ID"

      def initialize(app)
        @app = app
      end

      def call(env)
        # Use incoming request ID (from load balancer/proxy) or generate a new one
        request_id = env["HTTP_X_REQUEST_ID"]
        request_id = nil if request_id&.empty?
        request_id ||= SecureRandom.uuid

        # Sanitize — only allow safe characters
        request_id = request_id.gsub(/[^\w\-]/, "")[0, 255]

        # Make available to the app (e.g., for logging)
        env["tracks.request_id"] = request_id

        status, headers, body = @app.call(env)

        # Echo it back in the response
        headers[HEADER] = request_id

        [status, headers, body]
      end
    end
  end
end

# Register in your app:
#   use Tracks::Middleware::RequestId
#
# In your Logger middleware, include the request ID in log output:
#   request_id = env["tracks.request_id"] || "-"
#   puts "[#{request_id}] GET /posts → 200 (12ms)"
#
# This makes it easy to grep all log lines for a single request.
```

### Exercise 4 — Flash messages in session middleware

```ruby
# framework/lib/tracks/middleware/session.rb — add flash sweep to Session middleware

module Tracks
  module Middleware
    class Session
      KEY     = "_tracks_session"
      @@store = {}

      def initialize(app)
        @app = app
      end

      def call(env)
        sid = parse_cookie(env, KEY) || SecureRandom.hex(32)
        @@store[sid] ||= {}
        session = @@store[sid]

        # Sweep flash: remove entries that were already shown last request
        if session[:_flash_sweep]
          session[:_flash_sweep].each { |k| (session[:flash] ||= {}).delete(k) }
        end
        session[:_flash_sweep] = (session[:flash] || {}).keys

        env["tracks.session"]    = session
        env["tracks.session_id"] = sid

        status, headers, body = @app.call(env)
        headers["Set-Cookie"] = "#{KEY}=#{sid}; HttpOnly; Path=/"
        [status, headers, body]
      end

      private

      def parse_cookie(env, key)
        (env["HTTP_COOKIE"] || "").split("; ").each_with_object({}) do |pair, h|
          k, v = pair.split("=", 2); h[k] = v
        end[key]
      end
    end
  end
end

# framework/lib/tracks/base_controller.rb — add flash helper

module Tracks
  class BaseController
    # Access flash messages (hash stored in session[:flash])
    def flash
      session[:flash] ||= {}
    end
  end
end

# Usage in controllers:
# File: app/controllers/posts_controller.rb
class PostsController < Tracks::BaseController
  def create
    @post = Post.new(title: params["post[title]"], body: params["post[body]"])
    if @post.save
      flash[:notice] = "Post was successfully created."
      redirect_to "/posts/#{@post.id}"
    else
      flash[:error] = "Failed to create post."
      render :new
    end
  end

  def destroy
    Post.find(params["id"]).destroy
    flash[:notice] = "Post deleted."
    redirect_to "/posts"
  end
end

# In app/views/layouts/application.html.erb:
#
# <% if flash[:notice] %>
#   <div class="flash flash-notice"><%= h(flash[:notice]) %></div>
# <% end %>
# <% if flash[:error] %>
#   <div class="flash flash-error"><%= h(flash[:error]) %></div>
# <% end %>
```

### Exercise 5 — BasicAuth middleware

```ruby
# framework/lib/tracks/middleware/basic_auth.rb

require 'base64'

module Tracks
  module Middleware
    class BasicAuth
      def initialize(app, username:, password:)
        @app      = app
        @username = username
        @password = password
      end

      def call(env)
        unless authorized?(env)
          return [
            401,
            {
              "Content-Type"     => "text/plain",
              "WWW-Authenticate" => 'Basic realm="Restricted Area"'
            },
            ["HTTP Basic: Access denied."]
          ]
        end

        @app.call(env)
      end

      private

      def authorized?(env)
        auth_header = env["HTTP_AUTHORIZATION"] || ""
        return false unless auth_header.start_with?("Basic ")

        encoded    = auth_header.sub("Basic ", "")
        decoded    = Base64.decode64(encoded)
        user, pass = decoded.split(":", 2)

        # Use a constant-time comparison to avoid timing attacks
        secure_compare(user.to_s, @username) &&
          secure_compare(pass.to_s, @password)
      end

      def secure_compare(a, b)
        return false if a.length != b.length
        # XOR each byte — result is 0 only if all bytes match
        result = 0
        a.bytes.zip(b.bytes).each { |x, y| result |= x ^ y }
        result == 0
      end
    end
  end
end

# Register in your app (config.ru or application.rb):
#
#   use Tracks::Middleware::BasicAuth, username: "admin", password: "secret"
#
# Protects ALL routes. For partial protection, check the path:
#
# class App < Tracks::Application
#   routes do
#     get "/admin",        to: "admin#index"
#     get "/admin/stats",  to: "admin#stats"
#     resources :posts
#   end
# end
#
# config.ru:
#   admin_app = Rack::Builder.new do
#     use Tracks::Middleware::BasicAuth, username: "admin", password: "secret"
#     run App.new
#   end
#   run admin_app
```

---

## What You Learned

| Concept | Key point |
|---------|-----------|
| Middleware | wraps your app; can modify request/response |
| Rack contract | any object with `call(env)` returning `[status, headers, body]` |
| Middleware stack | chain of wrappers, built inside-out |
| Sessions | stateless HTTP + cookies → stateful sessions |
| CSRF | always include a secret token in forms |
| `reduce` | builds the middleware chain elegantly |
| Cookies | set via `Set-Cookie` header, read from `HTTP_COOKIE` |
