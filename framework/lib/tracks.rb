require_relative "tracks/version"
require_relative "tracks/router"
require_relative "tracks/request"
require_relative "tracks/response"
require_relative "tracks/erb_template"
require_relative "tracks/associations"
require_relative "tracks/validations"
require_relative "tracks/query"
require_relative "tracks/model"
require_relative "tracks/base_controller"
require_relative "tracks/dispatcher"
require_relative "tracks/middleware/logger"
require_relative "tracks/middleware/session"
require_relative "tracks/middleware/static"
require_relative "tracks/middleware_stack"
require_relative "tracks/application"

module Tracks
  module Helpers
    def h(text)
      text.to_s.gsub("&","&amp;").gsub("<","&lt;").gsub(">","&gt;").gsub('"',"&quot;")
    end

    def link_to(text, url)
      "<a href=\"#{url}\">#{h(text)}</a>"
    end

    def truncate(text, length: 30)
      text.to_s.length > length ? text.to_s[0, length] + "..." : text.to_s
    end
  end
end
