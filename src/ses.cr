require "json"
require "openssl"
require "uri"

module Alumna
  # Opened here so SigV4 and Transport can nest under SES.
  # The methods are in the class body below.
  class SES < Mailer
  end
end

require "./ses/sig_v4"
require "./ses/transport"

module Alumna
  # Amazon SES API v2 SendEmail.
  # One method: send. This is not a Redis-style holder.
  #
  # Success returns nil. HTTP errors, network errors, and TLS errors return MailError.
  # Empty region, empty keys, or a bad endpoint raise ArgumentError.
  #
  # Do not log the secret, the session token, or the Authorization header.
  # MailError text has those values removed.
  class SES < Mailer
    PATH         = "/v2/email/outbound-emails"
    SERVICE      = "ses"
    CONTENT_TYPE = "application/json"
    REGION       = /\A[a-z0-9-]+\z/

    @region : String
    @access_key_id : String
    @secret_access_key : String
    @session_token : String?
    @endpoint : URI
    @host : String
    @transport : Transport

    def self.from_env(*, endpoint : String? = nil, transport : Transport = HTTPTransport.new) : self
      new(
        region: env_value("AWS_REGION"),
        access_key_id: env_value("AWS_ACCESS_KEY_ID"),
        secret_access_key: env_value("AWS_SECRET_ACCESS_KEY"),
        session_token: ENV["AWS_SESSION_TOKEN"]?,
        endpoint: endpoint,
        transport: transport,
      )
    end

    def initialize(
      *,
      region : String,
      access_key_id : String,
      secret_access_key : String,
      session_token : String? = nil,
      endpoint : String? = nil,
      transport : Transport = HTTPTransport.new,
    )
      raise ArgumentError.new("region must not be empty") if region.empty?
      raise ArgumentError.new("region is invalid") unless region.matches?(REGION)
      raise ArgumentError.new("access_key_id must not be empty") if access_key_id.empty?
      raise ArgumentError.new("secret_access_key must not be empty") if secret_access_key.empty?
      if token = session_token
        raise ArgumentError.new("session_token must not be empty") if token.empty?
      end

      @region = region
      @access_key_id = access_key_id
      @secret_access_key = secret_access_key
      @session_token = session_token
      @endpoint = resolve_endpoint(region, endpoint)
      @host = endpoint_host(@endpoint)
      @transport = transport
    end

    def send(mail : Mail) : Nil | MailError
      body = message_body(mail)
      headers = signed_headers(body)
      status, response_body = @transport.post(@endpoint, headers, body)
      return nil if status >= 200 && status <= 299
      MailError.new(failure_message(status, response_body))
    rescue IO::Error | OpenSSL::Error
      MailError.new("mail send failed")
    end

    private def self.env_value(name : String) : String
      value = ENV[name]?
      raise ArgumentError.new("#{name} must not be empty") if value.nil? || value.empty?
      value
    end

    private def resolve_endpoint(region : String, endpoint : String?) : URI
      raw = endpoint || "https://email.#{region}.amazonaws.com#{PATH}"
      raise ArgumentError.new("endpoint must not be empty") if raw.empty?
      uri = URI.parse(raw)
      scheme = uri.scheme
      unless scheme == "http" || scheme == "https"
        raise ArgumentError.new("endpoint scheme must be http or https")
      end
      raise ArgumentError.new("endpoint userinfo is not supported") if uri.user || uri.password
      raise ArgumentError.new("endpoint query is not supported") if uri.query
      if uri.path.empty? || uri.path == "/"
        uri.path = PATH
      end
      uri
    end

    private def endpoint_host(uri : URI) : String
      host = uri.host
      raise ArgumentError.new("endpoint host must not be empty") if host.nil? || host.empty?
      host
    end

    private def host_header : String
      port = @endpoint.port
      return @host unless port
      default_port = @endpoint.scheme == "https" ? 443 : 80
      return @host if port == default_port
      "#{@host}:#{port}"
    end

    private def signed_headers(body : String) : HTTP::Headers
      amz_date = Time.utc.to_s("%Y%m%dT%H%M%SZ")
      host = host_header
      pairs = [
        {"content-type", CONTENT_TYPE},
        {"host", host},
        {"x-amz-date", amz_date},
      ]
      if token = @session_token
        pairs << {"x-amz-security-token", token}
      end
      signed = SigV4.sign(
        method: "POST",
        path: @endpoint.path,
        signed_headers: pairs,
        body: body,
        region: @region,
        service: SERVICE,
        access_key_id: @access_key_id,
        secret_access_key: @secret_access_key,
      )
      headers = HTTP::Headers{
        "Content-Type"         => CONTENT_TYPE,
        "Host"                 => host,
        "X-Amz-Date"           => amz_date,
        "X-Amz-Content-Sha256" => signed[:payload_hash],
        "Authorization"        => signed[:authorization],
      }
      if token = @session_token
        headers["X-Amz-Security-Token"] = token
      end
      headers
    end

    private def message_body(mail : Mail) : String
      String.build do |io|
        JSON.build(io) do |json|
          json.object do
            json.field "FromEmailAddress", mail.from
            json.field "Destination" do
              json.object do
                json.field "ToAddresses" do
                  json.array do
                    mail.to.each { |address| json.string address }
                  end
                end
              end
            end
            json.field "Content" do
              json.object do
                json.field "Simple" do
                  json.object do
                    json.field "Subject" do
                      json.object { write_content(json, mail.subject) }
                    end
                    json.field "Body" do
                      json.object do
                        json.field "Text" do
                          json.object { write_content(json, mail.text) }
                        end
                        if html = mail.html
                          unless html.empty?
                            json.field "Html" do
                              json.object { write_content(json, html) }
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
            if reply = mail.reply_to
              json.field "ReplyToAddresses" do
                json.array { json.string reply }
              end
            end
          end
        end
      end
    end

    private def write_content(json : JSON::Builder, value : String) : Nil
      json.field "Data", value
      json.field "Charset", "UTF-8"
    end

    private def failure_message(status : Int32, body : String) : String
      detail = error_detail(body)
      text = detail ? "SES send failed (#{status}): #{detail}" : "SES send failed (#{status})"
      redact(text)
    end

    private def error_detail(body : String) : String?
      return nil if body.empty?
      parsed = JSON.parse(body)
      hash = parsed.as_h?
      return nil unless hash
      value = hash["message"]? || hash["Message"]?
      return nil unless value
      value.as_s?
    rescue JSON::ParseException
      nil
    end

    private def redact(text : String) : String
      cleaned = text.gsub(@secret_access_key, "[redacted]")
      cleaned = cleaned.gsub(@access_key_id, "[redacted]")
      if token = @session_token
        cleaned = cleaned.gsub(token, "[redacted]")
      end
      cleaned
    end
  end
end
