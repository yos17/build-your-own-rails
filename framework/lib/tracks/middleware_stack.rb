module Tracks
  class MiddlewareStack
    def initialize
      @stack = []
    end

    def use(klass, *args)
      @stack << [klass, args]
    end

    def build(app)
      @stack.reverse.reduce(app) { |inner, (klass, args)| klass.new(inner, *args) }
    end
  end
end
