require 'json'

module Tracks
  class BaseController
    include Helpers

    attr_reader :request, :response, :params

    def initialize(request, response)
      @request  = request
      @response = response
      @params   = request.params.dup
    end

    # --- Rendering ---

    def render(template_name, layout: true)
      dir  = self.class.name.gsub("Controller","").gsub("::","/").downcase
      path = "app/views/#{dir}/#{template_name}.html.erb"
      content = ERB.new(File.read(path)).result(binding)

      if layout && File.exist?("app/views/layouts/application.html.erb")
        @_content = content
        full = ERB.new(File.read("app/views/layouts/application.html.erb")).result(binding)
        response.write(full)
      else
        response.write(content)
      end
    rescue => e
      response.status = 500
      response.write("Template error: #{e.message}<br><pre>#{e.backtrace.first(5).join("\n")}</pre>")
    end

    def render_json(data, status: 200)
      response.status = status
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

    # --- Session ---

    def session
      @request.env["tracks.session"] || {}
    end

    # --- Before actions ---

    def self.before_action(method_name, only: nil, except: nil)
      @before_actions ||= []
      @before_actions << { method: method_name, only: Array(only).map(&:to_sym), except: Array(except).map(&:to_sym) }
    end

    def self.before_actions
      @before_actions || []
    end

    def run_before_actions(action_name)
      self.class.before_actions.each do |ba|
        next if ba[:only].any?   && !ba[:only].include?(action_name.to_sym)
        next if ba[:except].any? &&  ba[:except].include?(action_name.to_sym)
        send(ba[:method])
        # Stop if redirected
        return if response.status >= 300
      end
    end
  end
end
