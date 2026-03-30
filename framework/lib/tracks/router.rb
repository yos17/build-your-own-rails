module Tracks
  class Router
    Route = Struct.new(:method, :pattern, :controller, :action)

    def initialize
      @routes = []
    end

    def get(path, to:);    add_route("GET",    path, to); end
    def post(path, to:);   add_route("POST",   path, to); end
    def patch(path, to:);  add_route("PATCH",  path, to); end
    def put(path, to:);    add_route("PUT",    path, to); end
    def delete(path, to:); add_route("DELETE", path, to); end

    def root(to:)
      get "/", to: to
    end

    def resources(name)
      n = name.to_s
      get    "/#{n}",          to: "#{n}#index"
      get    "/#{n}/new",      to: "#{n}#new"
      post   "/#{n}",          to: "#{n}#create"
      get    "/#{n}/:id",      to: "#{n}#show"
      get    "/#{n}/:id/edit", to: "#{n}#edit"
      patch  "/#{n}/:id",      to: "#{n}#update"
      delete "/#{n}/:id",      to: "#{n}#destroy"
    end

    def draw(&block)
      instance_eval(&block)
    end

    def route_for(method, path)
      # Normalize PATCH/PUT from _method override
      @routes.each do |route|
        next unless route.method == method
        params = match(route.pattern, path)
        return [route, params] if params
      end
      nil
    end

    def all_routes
      @routes
    end

    private

    def add_route(method, path, to)
      controller, action = to.split("#")
      @routes << Route.new(method, path, controller, action)
    end

    def match(pattern, path)
      regex_str = pattern.gsub(/:[a-z_]+/) { |m| "(?<#{m[1..]}>([^/]+))" }
      regex = Regexp.new("^#{regex_str}$")
      m = path.match(regex)
      m ? m.named_captures : nil
    end
  end
end
