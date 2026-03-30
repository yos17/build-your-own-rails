require 'uri'

module Tracks
  class Request
    attr_reader :env, :method, :path
    attr_accessor :params

    def initialize(env)
      @env    = env
      @method = env["REQUEST_METHOD"]
      @path   = env["PATH_INFO"]
      @params = parse_params
    end

    def get?;    @method == "GET";    end
    def post?;   @method == "POST";   end
    def patch?;  @method == "PATCH";  end
    def delete?; @method == "DELETE"; end

    def body
      @body ||= @env["rack.input"]&.read || ""
    end

    private

    def parse_params
      params = {}
      parse_query(@env["QUERY_STRING"] || "", params)
      if %w[POST PATCH PUT].include?(@method)
        parse_query(body, params)
      end
      params
    end

    def parse_query(str, params)
      str.split("&").each do |pair|
        key, value = pair.split("=", 2)
        next unless key && !key.empty?
        params[URI.decode_www_form_component(key)] =
          URI.decode_www_form_component(value.to_s)
      end
    end
  end
end
