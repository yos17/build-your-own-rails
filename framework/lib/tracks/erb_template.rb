require 'erb'

module Tracks
  module Views
    class ERBTemplate
      LAYOUT = "app/views/layouts/application.html.erb"

      def self.render(template_path, context, layout: true)
        raise "Template not found: #{template_path}" unless File.exist?(template_path)
        page = ERB.new(File.read(template_path)).result(context)

        if layout && File.exist?(LAYOUT)
          # Make page available as @_content in the layout
          context.eval("@_content = #{page.inspect}")
          ERB.new(File.read(LAYOUT)).result(context)
        else
          page
        end
      end
    end
  end
end
