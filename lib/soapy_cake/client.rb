# frozen_string_literal: true

require 'net/http'

module SoapyCake
  class Client
    HEADERS = { 'Content-Type' => 'application/soap+xml;charset=UTF-8' }.freeze

    def initialize(opts = {})
      @opts = opts
      @domain = fetch_opt(:domain) || raise(Error, 'Cake domain missing')
      @api_key = fetch_opt(:api_key) || raise(Error, 'Cake API key missing')
      @retry_count = fetch_opt(:retry_count, 4)
      @write_enabled = ['yes', true].include?(fetch_opt(:write_enabled))
      @time_converter = TimeConverter.new(fetch_opt(:time_zone), fetch_opt(:time_offset))
    end

    def xml_response?
      opts[:xml_response] == true
    end

    def read_only?
      !write_enabled
    end

    def run(request)
      check_write_enabled!(request)
      request.api_key = api_key
      request.time_converter = time_converter

      with_retries do
        begin
          response = Response.new(response_body(request), request.short_response?, time_converter)
          xml_response? ? response.to_xml : response.to_enum
        rescue RequestFailed => e
          raise RequestFailed.new(
            e.message,
            request_path: request.path,
            request_body: request.xml,
            response_body: e.response_body || response.body
          )
        end
      end
    end

    protected

    attr_reader :domain, :api_key, :time_converter, :opts, :retry_count, :write_enabled

    private

    def fetch_opt(key, fallback = nil)
      opts.fetch(key, ENV.fetch("CAKE_#{key.to_s.upcase}", fallback))
    end

    def check_write_enabled!(request)
      return if request.read_only? || write_enabled
      raise Error, 'Writes not enabled (pass write_enabled: true or set CAKE_WRITE_ENABLED=yes)'
    end

    def with_retries(&block)
      opts = { tries: retry_count + 1, on: [RateLimitError, SocketError], sleep: ->(n) { 3**n } }
      Retryable.retryable(opts, &block)
    end

    def logger
      @logger ||= opts[:logger] || (defined?(::Rails) && ::Rails.logger)
    end

    def log_curl_command(request)
      curl_headers = HEADERS.map { |k, v| "-H \"#{k}: #{v}\"" }.join(' ')
      curl_body = request.xml
                    .tr("\n", '')
                    .gsub(/>\s*</, '><')
                    .sub(request.api_key, '{{{ INSERT API KEY }}}')

      logger&.info("curl --data '#{curl_body}' #{curl_headers} https://#{domain}/#{request.path}")
    end

    def response_body(request)
      request.opts[:response].presence || http_response(request)
    end

    def http_response(request)
      logger&.info("soapy_cake:request #{request}")

      log_curl_command(request) if fetch_opt(:log_curl)

      http_request = Net::HTTP::Post.new(request.path, HEADERS)
      http_request.body = request.xml
      response = perform_http_request(http_request)

      unless response.is_a?(Net::HTTPSuccess)
        raise RequestFailed.new(
          "Request failed with HTTP #{response.code}",
          response_body: response.body
        )
      end

      response.body
    end

    def perform_http_request(http_request)
      Net::HTTP.start(
        domain,
        use_ssl: true,
        open_timeout: NET_TIMEOUT,
        read_timeout: NET_TIMEOUT
      ) do |http|
        http.request(http_request)
      end
    end
  end
end
