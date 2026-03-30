module Tracks
  class Application
    attr_reader :router

    def initialize
      @router     = Router.new
      @middleware = MiddlewareStack.new
      @middleware.use(Middleware::Static)
      @middleware.use(Middleware::Logger)
      @middleware.use(Middleware::Session)
    end

    def use(klass, *args)
      @middleware.use(klass, *args)
    end

    def routes(&block)
      @router.draw(&block)
    end

    def call(env)
      dispatcher = Dispatcher.new(@router)
      @middleware.build(dispatcher).call(env)
    end
  end
end
