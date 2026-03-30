module Tracks
  class Response
    attr_accessor :status, :headers, :body

    def initialize
      @status  = 200
      @headers = { "Content-Type" => "text/html; charset=utf-8" }
      @body    = []
    end

    def write(text)
      @body << text.to_s
    end

    def redirect_to(url, status: 302)
      @status  = status
      @headers["Location"] = url
      @body    = []
    end

    def to_rack
      [@status, @headers, @body]
    end
  end
end
