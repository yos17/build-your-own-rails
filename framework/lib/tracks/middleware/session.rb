require 'securerandom'

module Tracks
  module Middleware
    class Session
      KEY      = "_tracks_session"
      @@store  = {}

      def initialize(app)
        @app = app
      end

      def call(env)
        sid = parse_cookie(env, KEY) || SecureRandom.hex(32)
        @@store[sid] ||= {}
        env["tracks.session"]    = @@store[sid]
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
