require 'ddtrace/ext/runtime'
require 'ddtrace/ext/transport'

require 'ddtrace/runtime/container'

require 'ddtrace/profiling/transport/http/builder'
require 'ddtrace/profiling/transport/http/api'

require 'ddtrace/transport/http/adapters/net'
require 'ddtrace/transport/http/adapters/test'
require 'ddtrace/transport/http/adapters/unix_socket'

module Datadog
  module Profiling
    module Transport
      # TODO: Consolidate with Dataog::Transport::HTTP
      # Namespace for HTTP transport components
      module HTTP
        module_function

        # Builds a new Transport::HTTP::Client
        def new(&block)
          Builder.new(&block).to_transport
        end

        # Builds a new Transport::HTTP::Client with default settings
        # Pass a block to override any settings.
        def default(profiling_upload_timeout_seconds:, site: nil, api_key: nil, **options)
          new do |transport|
            transport.headers default_headers

            # Configure adapter & API
            if site && api_key
              configure_for_agentless(
                transport,
                profiling_upload_timeout_seconds: profiling_upload_timeout_seconds,
                site: site,
                api_key: api_key
              )
            else
              configure_for_agent(transport, profiling_upload_timeout_seconds: profiling_upload_timeout_seconds, **options)
            end

            # Additional options
            unless options.empty?
              # Add headers
              transport.headers options[:headers] if options.key?(:headers)

              # Execute on_build callback
              options[:on_build].call(transport) if options[:on_build].is_a?(Proc)
            end
          end
        end

        def default_headers
          {
            Datadog::Ext::Transport::HTTP::HEADER_META_LANG => Datadog::Ext::Runtime::LANG,
            Datadog::Ext::Transport::HTTP::HEADER_META_LANG_VERSION => Datadog::Ext::Runtime::LANG_VERSION,
            Datadog::Ext::Transport::HTTP::HEADER_META_LANG_INTERPRETER => Datadog::Ext::Runtime::LANG_INTERPRETER,
            Datadog::Ext::Transport::HTTP::HEADER_META_TRACER_VERSION => Datadog::Ext::Runtime::TRACER_VERSION
          }.tap do |headers|
            # Add container ID, if present.
            container_id = Datadog::Runtime::Container.container_id
            headers[Datadog::Ext::Transport::HTTP::HEADER_CONTAINER_ID] = container_id unless container_id.nil?
          end
        end

        def default_adapter
          :net_http
        end

        def default_hostname
          ENV.fetch(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST, Datadog::Ext::Transport::HTTP::DEFAULT_HOST)
        end

        def default_port
          ENV.fetch(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT, Datadog::Ext::Transport::HTTP::DEFAULT_PORT).to_i
        end

        private_class_method def configure_for_agent(transport, profiling_upload_timeout_seconds:, **options)
          apis = API.agent_defaults

          hostname = options[:hostname] || default_hostname
          port = options[:port] || default_port

          adapter_options = {}
          adapter_options[:timeout] = profiling_upload_timeout_seconds
          adapter_options[:ssl] = options[:ssl] if options.key?(:ssl)

          transport.adapter default_adapter, hostname, port, adapter_options
          transport.api API::V1, apis[API::V1], default: true
        end

        private_class_method def configure_for_agentless(transport, profiling_upload_timeout_seconds:, site:, api_key:)
          apis = API.api_defaults

          site_uri = URI(format(Datadog::Ext::Profiling::Transport::HTTP::URI_TEMPLATE_DD_API, site))
          hostname = site_uri.host
          port = site_uri.port

          transport.adapter(
            default_adapter,
            hostname,
            port,
            timeout: profiling_upload_timeout_seconds,
            ssl: site_uri.scheme == 'https'
          )
          transport.api(API::V1, apis[API::V1], default: true)
          transport.headers(Datadog::Ext::Transport::HTTP::HEADER_DD_API_KEY => api_key)
        end

        # Add adapters to registry
        Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::Net, :net_http)
        Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::Test, :test)
        Builder::REGISTRY.set(Datadog::Transport::HTTP::Adapters::UnixSocket, :unix)
      end
    end
  end
end
