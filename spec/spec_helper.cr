require "spec"
require "mutex"
require "../src/alumna-ses"

class FakeTransport < Alumna::SES::Transport
  record Call, uri : URI, headers : HTTP::Headers, body : String

  getter calls = [] of Call
  property status : Int32 = 200
  property response_body : String = %({"MessageId":"m-1"})
  property error : Exception? = nil
  @mutex = Sync::Mutex.new

  def post(uri : URI, headers : HTTP::Headers, body : String) : {Int32, String}
    @mutex.synchronize do
      @calls << Call.new(uri, headers.dup, body)
    end
    if err = @error
      raise err
    end
    {@status, @response_body}
  end
end

def sample_mail(
  *,
  to : String | Array(String) = "to@example.com",
  text : String = "Hello",
  html : String? = nil,
  reply_to : String? = nil,
) : Alumna::Mail
  Alumna::Mail.new(
    from: "from@example.com",
    to: to,
    subject: "Subject",
    text: text,
    html: html,
    reply_to: reply_to,
  )
end

def ses_mailer(
  *,
  region : String = "sa-east-1",
  access_key_id : String = "AKIDEXAMPLE",
  secret_access_key : String = "secret-key",
  session_token : String? = nil,
  endpoint : String? = nil,
  transport : Alumna::SES::Transport = FakeTransport.new,
) : Alumna::SES
  Alumna::SES.new(
    region: region,
    access_key_id: access_key_id,
    secret_access_key: secret_access_key,
    session_token: session_token,
    endpoint: endpoint,
    transport: transport,
  )
end

def with_env(values : Hash(String, String?), &)
  previous = Hash(String, String?).new
  values.each_key { |key| previous[key] = ENV[key]? }
  begin
    values.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
    yield
  ensure
    previous.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end
