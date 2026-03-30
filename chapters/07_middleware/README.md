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
