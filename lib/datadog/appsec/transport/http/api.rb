# typed: ignore

require_relative '../../../core/encoding'

require_relative '../../../../ddtrace/transport/http/api/map'
# TODO: because of include in http/negotiation
#require_relative '../../../../ddtrace/transport/http/api/spec'
require_relative 'api/spec'

require_relative 'negotiation'
require_relative 'config'

module Datadog
  module AppSec
    module Transport
      module HTTP
        # Namespace for API components
        module API
          # Default API versions
          ROOT = 'root'.freeze
          V7 = 'v0.7'.freeze

          module_function

          def defaults
            Datadog::Transport::HTTP::API::Map[
              ROOT => Spec.new do |s|
                s.info = Negotiation::API::Endpoint.new(
                  '/info'.freeze,
                )
              end,
              V7 => Spec.new do |s|
                s.config = Config::API::Endpoint.new(
                  '/v0.7/config'.freeze,
                  Core::Encoding::JSONEncoder,
                )
              end,
            ]
          end
        end
      end
    end
  end
end
