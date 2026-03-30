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
