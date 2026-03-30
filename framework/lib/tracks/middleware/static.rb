module Tracks
  module Middleware
    class Static
      MIME = {
        ".html" => "text/html", ".css" => "text/css",
        ".js"   => "application/javascript", ".png" => "image/png",
        ".jpg"  => "image/jpeg", ".svg" => "image/svg+xml",
        ".ico"  => "image/x-icon", ".txt" => "text/plain"
      }

      def initialize(app, root: "public")
        @app  = app
        @root = root
      end

      def call(env)
        path = File.join(@root, env["PATH_INFO"])
        if File.file?(path)
          ext  = File.extname(path)
          mime = MIME[ext] || "application/octet-stream"
          return [200, {"Content-Type" => mime}, [File.read(path)]]
        end
        @app.call(env)
      end
    end
  end
end
