module Tracks
  module Middleware
    class Logger
      def initialize(app)
        @app = app
      end

      def call(env)
        t0 = Time.now
        status, headers, body = @app.call(env)
        ms = ((Time.now - t0) * 1000).round(1)

        color = case status
                when 200..299 then "\e[32m"
                when 300..399 then "\e[34m"
                when 400..499 then "\e[33m"
                else "\e[31m"
                end

        STDOUT.puts "#{color}#{env['REQUEST_METHOD']} #{env['PATH_INFO']} → #{status} (#{ms}ms)\e[0m"
        [status, headers, body]
      end
    end
  end
end
