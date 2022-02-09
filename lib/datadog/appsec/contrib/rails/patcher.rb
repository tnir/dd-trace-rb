# typed: ignore

require 'datadog/core/utils/only_once'

require 'datadog/appsec/contrib/patcher'
require 'datadog/appsec/contrib/rails/integration'
require 'datadog/appsec/contrib/rails/framework'
require 'datadog/appsec/contrib/rack/request_middleware'

require 'datadog/tracing/contrib/rack/middlewares'

module Datadog
  module AppSec
    module Contrib
      module Rails
        # Patcher for AppSec on Rails
        module Patcher
          include Datadog::AppSec::Contrib::Patcher

          BEFORE_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Core::Utils::OnlyOnce.new }
          AFTER_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Core::Utils::OnlyOnce.new }

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            patch_before_intialize
            patch_after_intialize

            Patcher.instance_variable_set(:@patched, true)
          end

          def patch_before_intialize
            ::ActiveSupport.on_load(:before_initialize) do
              Datadog::AppSec::Contrib::Rails::Patcher.before_intialize(self)
            end
          end

          def before_intialize(app)
            BEFORE_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
              # Middleware must be added before the application is initialized.
              # Otherwise the middleware stack will be frozen.
              # Sometimes we don't want to activate middleware e.g. OpenTracing, etc.
              add_middleware(app) if Datadog.configuration[:rails][:middleware]
            end
          end

          def add_middleware(app)
            # Add trace middleware
            if include_middleware?(Datadog::Tracing::Contrib::Rack::TraceMiddleware, app)
              app.middleware.insert_after(Datadog::Tracing::Contrib::Rack::TraceMiddleware,
                                          Datadog::AppSec::Contrib::Rack::RequestMiddleware)
            else
              app.middleware.insert_before(0, Datadog::AppSec::Contrib::Rack::RequestMiddleware)
            end
          end

          def include_middleware?(middleware, app)
            found = false

            # find tracer middleware reference in Rails::Configuration::MiddlewareStackProxy
            app.middleware.instance_variable_get(:@operations).each do |operation|
              args = case operation
                     when Array
                       # rails 5.2
                       _op, args = operation
                       args
                     when Proc
                       if operation.binding.local_variables.include?(:args)
                         # rails 6.0, 6.1
                         operation.binding.local_variable_get(:args)
                       else
                         # rails 7.0 uses ... to pass args
                         args_getter = Class.new do
                           def method_missing(_op, *args) # rubocop:disable Style/MissingRespondToMissing
                             args
                           end
                         end.new
                         operation.call(args_getter)
                       end
                     else
                       # unknown, pass through
                       []
                     end

              found = true if args.include?(middleware)
            end

            found
          end

          def inspect_middlewares(app)
            Datadog.logger.debug { 'Rails middlewares: ' << app.middleware.map(&:inspect).inspect }
          end

          def patch_after_intialize
            ::ActiveSupport.on_load(:after_initialize) do
              Datadog::AppSec::Contrib::Rails::Patcher.after_intialize(self)
            end
          end

          def after_intialize(app)
            AFTER_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
              # Finish configuring the tracer after the application is initialized.
              # We need to wait for some things, like application name, middleware stack, etc.
              setup_security
              inspect_middlewares(app)
            end
          end

          def setup_security
            Datadog::AppSec::Contrib::Rails::Framework.setup
          end
        end
      end
    end
  end
end