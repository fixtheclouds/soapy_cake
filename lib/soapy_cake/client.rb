require 'sekken'
require 'active_support/core_ext/time/zones'

module SoapyCake
  class Client
    attr_reader :service, :api_key, :domain, :role

    def initialize(service, opts = {})
      @service = service.to_sym
      @version = opts[:version]
      @role = opts[:role] || :admin

      @domain = opts.fetch(:domain) do
        if ENV['CAKE_DOMAIN'].present?
          ENV['CAKE_DOMAIN']
        else
          raise 'We need a domain'
        end
      end

      @api_key = opts.fetch(:api_key) do
        if opts[:username] && opts[:password]
          get_api_key(opts[:username], opts[:password])
        elsif ENV['CAKE_API_KEY']
          ENV['CAKE_API_KEY']
        else
          raise 'We need an API key here!'
        end
      end
    end

    def self.method_missing(method, opts = {})
      new(method, opts)
    end

    def sekken_client(method)
      self.class.sekken_client(wsdl_url(version(method)))
    end

    def self.sekken_client(url)
      @sekken_clients ||= {}
      @sekken_clients[url] ||= Sekken.new(url)
    end

    def method_missing(method, opts = {})
      if supported?(method)
        method = method.to_s
        operation = sekken_client(method).operation(service, "#{service}Soap12", method.camelize)
        operation.body = build_body(method, opts)
        process_response(method, operation.call.body)
      else
        super
      end
    end

    def known_params_for(method)
      method = method.to_s
      operation = sekken_client(method).operation(service, "#{service}Soap12", method.camelize)
      operation.example_body
    end

    private

    def build_body(method, opts)
      {
        method.camelize.to_sym => { api_key: api_key }.merge(
          opts.each_with_object({}) do |(key, value), memo|
            memo[key] = format_param(value)
          end
        )
      }
    end

    def format_param(value)
      case value
      when Time
        value.utc.strftime('%Y-%m-%dT%H:%M:%S')
      when Date
        value.strftime('%Y-%m-%dT00:00:00')
      else
        value
      end
    end

    def process_response(method, response)
      Time.use_zone('UTC') do
        raise RequestUnsuccessful, response[:fault][:reason][:text] if response[:fault]
        node_name = {
          'affiliate_summary' => 'affiliates',
          'affiliate_tags' => 'tags',
          'offer_summary' => 'offers',
          'campaign_summary' => 'campaigns',
          'offer_feed' => 'offers',
        }.fetch(method, method)

        result = response[:"#{method}_response"][:"#{method}_result"]
        raise RequestUnsuccessful, result[:message] if result[:success] == false
        return result unless result_has_collection?(result, method)
        extract_collection(node_name, result).
          map { |hash| remove_prefix(node_name, hash) }
      end
    end

    def result_has_collection?(result, method)
      !result.key?(:message) && !method.to_s.starts_with?('get_')
    end

    def extract_collection(node_name, response)
      node_name = node_name.to_sym
      if response.key?(node_name)
        return [] if response[node_name].nil?
        response = response[node_name]
      end
      [response[response.keys.first]].flatten
    end

    def remove_prefix(prefix, object)
      object.each_with_object({}) do |(k, v), m|
        prefix_ = "#{prefix.singularize}_"
        if k.to_s.start_with?(prefix_)
          m[k[(prefix_.size)..-1].to_sym] = v
        else
          m[k] = v
        end
      end
    end

    def get_api_key(username, password)
      operation = sekken_client(:get_api_key).operation('get', 'getSoap12', 'GetAPIKey')
      operation.body = { GetAPIKey: { username: username, password: password } }
      response = operation.call.body
      response[:get_api_key_response][:get_api_key_result]
    end

    def wsdl_url(version)
      role_path = (role && role != :admin) ? "/#{role}" : nil
      "https://#{domain}#{role_path}/api/#{version}/#{service}.asmx?WSDL"
    end

    def version(method)
      API_VERSIONS[role][service][method.to_sym]
    end

    def supported?(method)
      API_VERSIONS[role][service].keys.include?(method)
    end

    class RequestUnsuccessful < RuntimeError; end
  end
end
