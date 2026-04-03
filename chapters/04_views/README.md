# Chapter 4 — Views: Rendering HTML

## What is a View?

A view is a template — HTML with Ruby code embedded in it. Rails uses **ERB** (Embedded Ruby), which is built into Ruby's standard library.

```erb
<!-- app/views/posts/index.html.erb -->
<h1>All Posts</h1>

<% @posts.each do |post| %>
  <div class="post">
    <h2><%= post.title %></h2>
    <p><%= post.body %></p>
    <a href="/posts/<%= post.id %>">Read more</a>
  </div>
<% end %>
```

ERB tags:
- `<% code %>` — execute Ruby, no output
- `<%= expression %>` — execute and output the result
- `<%# comment %>` — comment, not executed

---

## How ERB Works

ERB is simple: it scans a template, finds the tags, and replaces them with Ruby execution:

```ruby
require 'erb'

template = "Hello, <%= name %>! Today is <%= Date.today %>."
name = "Yosia"

result = ERB.new(template).result(binding)
# => "Hello, Yosia! Today is 2026-03-28."
```

`binding` captures the current context. ERB evaluates the Ruby expressions inside the binding, so `name` refers to our local variable.

---

## Building the Template Renderer

```ruby
# framework/lib/tracks/erb_template.rb

require 'erb'

module Tracks
  module Views
    class ERBTemplate
      def self.render(template_path, context_binding)
        unless File.exist?(template_path)
          raise "Template not found: #{template_path}"
        end

        template_content = File.read(template_path)
        ERB.new(template_content).result(context_binding)
      end
    end
  end
end
```

That's the core of a view renderer. The rest is making it convenient.

---

## Layouts — The Shared Wrapper

Every page usually shares the same header, footer, and `<html>` structure. Rails calls this a **layout**.

```erb
<!-- app/views/layouts/application.html.erb -->
<!DOCTYPE html>
<html>
  <head>
    <title>My App</title>
    <link rel="stylesheet" href="/application.css">
  </head>
  <body>
    <nav>
      <a href="/">Home</a> |
      <a href="/posts">Posts</a>
    </nav>

    <main>
      <%= yield %>
    </main>

    <footer>Built with Tracks</footer>
  </body>
</html>
```

`<%= yield %>` is where the specific page content goes in.

Let's update the renderer to support layouts:

```ruby
# framework/lib/tracks/erb_template.rb

module Tracks
  module Views
    class ERBTemplate
      LAYOUT_PATH = "app/views/layouts/application.html.erb"

      def self.render(template_path, context_binding, layout: true)
        raise "Template not found: #{template_path}" unless File.exist?(template_path)

        # Render the specific page template
        page_content = ERB.new(File.read(template_path)).result(context_binding)

        # Wrap in layout if it exists
        if layout && File.exist?(LAYOUT_PATH)
          # Make page_content available to layout via a block
          layout_template = File.read(LAYOUT_PATH)
          ERB.new(layout_template).result_with_hash({ content: page_content })
        else
          page_content
        end
      end
    end
  end
end
```

In the layout, `yield` returns the page content. How? We use a clever trick with ERB's block:

```ruby
# The layout uses yield — we provide a block that returns page_content
erb = ERB.new(layout_content)
erb.result_with_hash(content: page_content)
```

Actually, the cleaner way Rails does it — uses a `content_for` helper that stores blocks in a hash, then `yield :content` retrieves them. Let's implement a simpler version:

```ruby
module Tracks
  class BaseController
    def render(template_name, layout: true)
      controller_dir = self.class.name
        .gsub("Controller", "").gsub("::", "/").downcase

      template_path = "app/views/#{controller_dir}/#{template_name}.html.erb"
      raise "Template not found: #{template_path}" unless File.exist?(template_path)

      # Render the page content
      page_content = ERB.new(File.read(template_path)).result(binding)

      if layout && File.exist?("app/views/layouts/application.html.erb")
        layout_src = File.read("app/views/layouts/application.html.erb")
        # Evaluate layout; when it hits `yield`, give it page_content
        @_content = page_content
        full_page = ERB.new(layout_src).result(binding)
        response.write(full_page)
      else
        response.write(page_content)
      end
    end
  end
end
```

In the layout template, `yield` works because we're evaluating in the controller's binding, and we set `@_content`. Actually, we override `yield`:

The cleanest approach is what Rails does — `content_for` with a block:

```erb
<!-- layout: instead of yield, use a helper -->
<%= @_content %>
```

Or the proper way — set `@content_for_layout` and reference it.

---

## View Helpers

Helpers are methods you call inside templates to reduce repetition:

```ruby
# framework/lib/tracks/helpers.rb

module Tracks
  module Helpers
    # link_to "Posts", "/posts"  =>  <a href="/posts">Posts</a>
    def link_to(text, url, **attrs)
      attr_str = attrs.map { |k, v| "#{k}=\"#{v}\"" }.join(" ")
      "<a href=\"#{url}\" #{attr_str}>#{h(text)}</a>"
    end

    # Escape HTML to prevent XSS
    def h(text)
      text.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub('"', "&quot;")
    end

    # form_tag "/posts", method: "post"
    def form_tag(url, method: "post", &block)
      # HTML forms only support GET and POST
      # For PATCH/DELETE, use a hidden _method field
      actual_method = method.upcase
      form_method   = ["GET", "POST"].include?(actual_method) ? actual_method : "POST"
      method_field  = actual_method != form_method ?
        "<input type='hidden' name='_method' value='#{actual_method}'>" : ""

      content = block ? yield : ""
      "<form action=\"#{url}\" method=\"#{form_method}\">#{method_field}#{content}</form>"
    end

    # text_field :post, :title, value: "Hello"
    def text_field(obj_name, attr, **opts)
      value = opts.delete(:value) || ""
      "<input type=\"text\" name=\"#{obj_name}[#{attr}]\" value=\"#{h(value)}\">"
    end

    def submit_tag(label = "Submit")
      "<input type=\"submit\" value=\"#{h(label)}\">"
    end

    # truncate("Hello world this is long", length: 10) => "Hello w..."
    def truncate(text, length: 30)
      text.length > length ? text[0, length] + "..." : text
    end

    def time_ago(time)
      diff = Time.now - time
      case diff
      when 0..59      then "#{diff.to_i} seconds ago"
      when 60..3599   then "#{(diff/60).to_i} minutes ago"
      when 3600..86399 then "#{(diff/3600).to_i} hours ago"
      else                  "#{(diff/86400).to_i} days ago"
      end
    end
  end
end
```

Include helpers in the base controller so templates can use them:

```ruby
class BaseController
  include Tracks::Helpers
end
```

---

## Partials — Reusable Template Pieces

Partials are template fragments you can reuse. Rails uses `_` prefix by convention:

```erb
<!-- app/views/posts/_post.html.erb -->
<div class="post">
  <h2><%= post.title %></h2>
  <p><%= truncate(post.body) %></p>
</div>
```

```erb
<!-- app/views/posts/index.html.erb -->
<h1>Posts</h1>
<% @posts.each do |post| %>
  <%= render_partial "posts/post", post: post %>
<% end %>
```

Building `render_partial`:

```ruby
def render_partial(name, locals = {})
  parts    = name.split("/")
  dir      = parts[0..-2].join("/")
  filename = "_#{parts.last}.html.erb"
  path     = "app/views/#{dir}/#{filename}"

  raise "Partial not found: #{path}" unless File.exist?(path)

  # Create a clean binding with locals available
  template = File.read(path)
  ctx = Object.new
  locals.each { |k, v| ctx.instance_variable_set("@#{k}", v) }
  # Also make them available as local variables via instance_eval
  ctx.instance_eval do
    locals.each { |k, v| define_singleton_method(k) { v } }
  end
  ERB.new(template).result(ctx.instance_eval { binding })
end
```

---

## A Real View

```erb
<!-- app/views/posts/show.html.erb -->
<article>
  <h1><%= h(@post.title) %></h1>
  <p class="meta">
    Posted <%= time_ago(@post.created_at) %>
    by <%= h(@post.author_name) %>
  </p>
  <div class="body">
    <%= @post.body %>
  </div>

  <%= link_to "← Back", "/posts" %>
  <%= link_to "Edit", "/posts/#{@post.id}/edit" %>
</article>
```

---

## Exercises

1. Add a `number_to_currency` helper: `number_to_currency(19.99)` → `"$19.99"`
2. Add `content_for` and `yield :section` — let templates inject content into specific layout sections (like `<head>` extra scripts)
3. Add `cycle("odd", "even")` helper for alternating CSS classes in loops
4. Build `form_for(@post)` that generates a form with the object's current values pre-filled
5. Add template caching — don't re-read files from disk on every request (hint: use a class-level hash)

---

## Solutions

### Exercise 1 — `number_to_currency` helper

```ruby
# framework/lib/tracks.rb (or framework/lib/tracks/helpers.rb) — add to Helpers module

module Tracks
  module Helpers
    # number_to_currency(19.99)      => "$19.99"
    # number_to_currency(1234.5)     => "$1,234.50"
    # number_to_currency(0)          => "$0.00"
    # number_to_currency(9.9, unit: "€", separator: ",", delimiter: ".") => "€9,90"
    def number_to_currency(amount, unit: "$", separator: ".", delimiter: ",", precision: 2)
      rounded = amount.round(precision)
      integer_part, decimal_part = ("%.#{precision}f" % rounded).split(".")

      # Insert thousands delimiter
      integer_with_delimiters = integer_part
        .chars
        .reverse
        .each_slice(3)
        .map(&:join)
        .join(delimiter)
        .reverse

      "#{unit}#{integer_with_delimiters}#{separator}#{decimal_part}"
    end
  end
end

# Usage in any ERB template (helpers are included in BaseController):
# <%= number_to_currency(19.99) %>         → $19.99
# <%= number_to_currency(1234.567) %>      → $1,234.57
# <%= number_to_currency(price) %>
```

### Exercise 2 — `content_for` and `yield :section`

```ruby
# framework/lib/tracks/base_controller.rb — add content_for support

module Tracks
  class BaseController
    # Store named content blocks
    def content_for(section, &block)
      @_content_sections ||= {}
      @_content_sections[section.to_sym] = block ? yield : ""
    end

    # Called in layouts: yield :head, yield :scripts, etc.
    # Overrides Ruby's built-in yield when called with an argument.
    def yield_section(section)
      @_content_sections ||= {}
      @_content_sections[section.to_sym] || ""
    end
  end
end

# framework/lib/tracks/base_controller.rb — update render to expose yield_section
#
# In the layout template, use yield_section(:name) instead of plain yield.
# The @_content variable already holds the main page body.

# Usage in a page template (app/views/posts/show.html.erb):
#
#   <% content_for :title do %>Posts — <%= h(@post.title) %><% end %>
#   <% content_for :scripts do %>
#     <script src="/js/highlight.js"></script>
#   <% end %>
#
#   <article>
#     <h1><%= h(@post.title) %></h1>
#     <p><%= @post.body %></p>
#   </article>

# In the layout (app/views/layouts/application.html.erb):
#
#   <head>
#     <title><%= yield_section(:title) || "My App" %></title>
#     <%= yield_section(:head) %>
#   </head>
#   <body>
#     <%= @_content %>
#     <%= yield_section(:scripts) %>
#   </body>

# The render method in base_controller already evaluates in the controller's
# binding, so content_for and yield_section are naturally available in templates.
```

### Exercise 3 — `cycle` helper

```ruby
# Add to Tracks::Helpers module

module Tracks
  module Helpers
    # cycle("odd", "even") returns values in rotation on successive calls
    # Useful for alternating CSS classes in loops.
    #
    # <% @posts.each do |post| %>
    #   <div class="post <%= cycle('odd', 'even') %>">...</div>
    # <% end %>

    def cycle(*values, name: :default)
      @_cycles ||= {}
      @_cycles[name] ||= 0
      value = values[@_cycles[name] % values.size]
      @_cycles[name] += 1
      value
    end

    def reset_cycle(name = :default)
      @_cycles ||= {}
      @_cycles[name] = 0
    end
  end
end

# Usage in a template:
#
# <ul>
# <% @posts.each do |post| %>
#   <li class="<%= cycle('odd', 'even') %>">
#     <%= h(post.title) %>
#   </li>
# <% end %>
# </ul>
#
# Multiple independent cycles in the same template:
# <% @posts.each do |post| %>
#   <tr class="<%= cycle('odd', 'even', name: :rows) %>">
#     <td style="color: <%= cycle('red', 'green', 'blue', name: :colors) %>">
#       <%= h(post.title) %>
#     </td>
#   </tr>
# <% end %>
```

### Exercise 4 — `form_for(@post)` with pre-filled values

```ruby
# Add to Tracks::Helpers module

module Tracks
  module Helpers
    # form_for(@post) generates a form pointed at the right URL
    # with existing values pre-filled.
    #
    # New record  → POST /posts
    # Persisted   → PATCH /posts/5  (via _method hidden field)
    #
    # Usage in a template:
    #   <%= form_for(@post) do |f| %>
    #     <%= f.text_field :title %>
    #     <%= f.textarea :body %>
    #     <%= f.submit %>
    #   <% end %>

    def form_for(object, url: nil, &block)
      model_name = object.class.name.downcase          # "post"
      url      ||= object.persisted? ? "/#{model_name}s/#{object.id}" : "/#{model_name}s"
      method     = object.persisted? ? "PATCH" : "POST"
      form_method = "POST"
      method_field = method != "POST" ?
        "<input type='hidden' name='_method' value='#{method}'>" : ""

      # Form builder object that scopes field names to the model
      builder = FormBuilder.new(model_name, object)
      inner = block.call(builder)

      "<form action=\"#{url}\" method=\"#{form_method}\">#{method_field}#{inner}</form>"
    end

    class FormBuilder
      def initialize(model_name, object)
        @model_name = model_name
        @object     = object
      end

      def text_field(attr, placeholder: nil)
        value = @object.respond_to?(attr) ? @object.send(attr).to_s : ""
        ph = placeholder ? " placeholder=\"#{placeholder}\"" : ""
        "<input type=\"text\" name=\"#{@model_name}[#{attr}]\" value=\"#{h(value)}\"#{ph}>"
      end

      def textarea(attr, rows: 8)
        value = @object.respond_to?(attr) ? @object.send(attr).to_s : ""
        "<textarea name=\"#{@model_name}[#{attr}]\" rows=\"#{rows}\">#{h(value)}</textarea>"
      end

      def hidden_field(attr, value: nil)
        val = value || (@object.respond_to?(attr) ? @object.send(attr).to_s : "")
        "<input type=\"hidden\" name=\"#{@model_name}[#{attr}]\" value=\"#{h(val)}\">"
      end

      def submit(label = nil)
        label ||= @object.persisted? ? "Update" : "Create"
        "<input type=\"submit\" value=\"#{label}\">"
      end

      private

      def h(text)
        text.to_s
          .gsub("&", "&amp;").gsub("<", "&lt;")
          .gsub(">", "&gt;").gsub('"', "&quot;")
      end
    end
  end
end

# Usage in app/views/posts/new.html.erb:
#
#   <h1>New Post</h1>
#   <%= form_for(@post) do |f| %>
#     <p><label>Title<br><%= f.text_field :title, placeholder: "Enter title..." %></label></p>
#     <p><label>Body<br><%= f.textarea :body, rows: 10 %></label></p>
#     <%= f.submit %>
#   <% end %>
#
# Usage in app/views/posts/edit.html.erb:
#
#   <h1>Edit Post</h1>
#   <%= form_for(@post) do |f| %>
#     <p><label>Title<br><%= f.text_field :title %></label></p>
#     <p><label>Body<br><%= f.textarea :body %></label></p>
#     <%= f.submit "Save Changes" %>
#   <% end %>
#   <%# Generates: <form action="/posts/5" method="POST">
#                    <input type="hidden" name="_method" value="PATCH"> ... %>
```

### Exercise 5 — Template caching

```ruby
# framework/lib/tracks/erb_template.rb — add a class-level cache

module Tracks
  module Views
    class ERBTemplate
      # Cache compiled ERB objects, keyed by file path + mtime
      @cache = {}
      @cache_enabled = (ENV["RACK_ENV"] == "production")

      class << self
        attr_accessor :cache_enabled

        def render(template_path, context_binding, layout: true)
          raise "Template not found: #{template_path}" unless File.exist?(template_path)

          page_content = compiled(template_path).result(context_binding)

          if layout && File.exist?("app/views/layouts/application.html.erb")
            # The layout references @_content, which must be set in context_binding
            # (BaseController#render already sets @_content = page_content)
            compiled("app/views/layouts/application.html.erb").result(context_binding)
          else
            page_content
          end
        end

        def invalidate_cache!
          @cache.clear
        end

        private

        def compiled(path)
          if @cache_enabled
            mtime = File.mtime(path).to_i
            key   = "#{path}:#{mtime}"

            unless @cache[key]
              # Remove old version of this path if present
              @cache.delete_if { |k, _| k.start_with?("#{path}:") }
              @cache[key] = ERB.new(File.read(path))
            end

            @cache[key]
          else
            # Development: always re-read from disk for live reloading
            ERB.new(File.read(path))
          end
        end
      end
    end
  end
end

# To enable caching in production (config.ru or environment config):
# Tracks::Views::ERBTemplate.cache_enabled = true
#
# In development it's off by default, so templates reload on every request.
# In production, templates are compiled once and reused.
```

---

## What You Learned

| Concept | Key point |
|---------|-----------|
| ERB | embed Ruby in HTML with `<% %>` and `<%= %>` |
| `binding` | captures current context — variables, self, methods |
| Layouts | shared wrapper with `yield` for page content |
| Helpers | Ruby methods available inside templates |
| `h(text)` | HTML escaping — prevents XSS attacks |
| Partials | reusable template pieces, `_` prefix convention |
| `define_singleton_method` | add a method to just one object |
