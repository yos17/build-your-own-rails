module Tracks
  class Dispatcher
    def initialize(router)
      @router = router
    end

    def call(env)
      request  = Request.new(env)
      response = Response.new

      # Handle _method override (for PATCH/DELETE from HTML forms)
      method = request.method
      if method == "POST" && request.params["_method"]
        method = request.params["_method"].upcase
      end

      route, url_params = @router.route_for(method, request.path)

      unless route
        response.status = 404
        response.write("<h1>404 Not Found</h1><p>No route for #{method} #{request.path}</p>")
        return response.to_rack
      end

      # Merge URL params into request params
      request.params.merge!(url_params)

      # Find controller class: "posts" → PostsController
      klass_name = "#{route.controller.split('_').map(&:capitalize).join}Controller"
      controller_class = Object.const_get(klass_name)
      controller = controller_class.new(request, response)

      # Run before_actions, then the action
      controller.run_before_actions(route.action)
      controller.send(route.action) if response.status < 300

      response.to_rack

    rescue NameError => e
      response = Response.new
      response.status = 500
      response.write("<h1>500 Error</h1><p>Controller not found: #{e.message}</p>")
      response.to_rack
    rescue => e
      response = Response.new
      response.status = 500
      response.write("<h1>500 Error</h1><p>#{e.message}</p><pre>#{e.backtrace.first(10).join("\n")}</pre>")
      response.to_rack
    end
  end
end
