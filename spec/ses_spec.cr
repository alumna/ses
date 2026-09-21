require "./spec_helper"
require "http/server"
require "socket"
require "wait_group"

private def wait_for_port(port : Int32) : Nil
  deadline = Time.instant + 2.seconds
  loop do
    begin
      TCPSocket.new("127.0.0.1", port).close
      return
    rescue Socket::ConnectError
      raise "server did not start" if Time.instant > deadline
      Fiber.yield
    end
  end
end

private def mail_error(result : Nil | Alumna::MailError) : Alumna::MailError
  result.should be_a(Alumna::MailError)
  if result.is_a?(Alumna::MailError)
    result
  else
    raise "expected MailError"
  end
end

describe Alumna::SES do
  it "posts SendEmail JSON and returns nil on success" do
    transport = FakeTransport.new
    mailer = ses_mailer(transport: transport)
    mailer.send(sample_mail(to: ["a@example.com", "b@example.com"], text: "Olá", html: "<p>Olá</p>", reply_to: "reply@example.com")).should be_nil

    transport.calls.size.should eq(1)
    call = transport.calls[0]
    call.uri.host.should eq("email.sa-east-1.amazonaws.com")
    call.uri.scheme.should eq("https")
    call.uri.path.should eq("/v2/email/outbound-emails")
    call.headers["Host"].should eq("email.sa-east-1.amazonaws.com")
    call.headers["Content-Type"].should eq("application/json")
    call.headers["X-Amz-Date"].should match(/\A\d{8}T\d{6}Z\z/)
    call.headers["Authorization"].should contain("Credential=AKIDEXAMPLE/")
    call.headers["Authorization"].should contain("/sa-east-1/ses/aws4_request")
    call.headers["X-Amz-Security-Token"]?.should be_nil

    payload = JSON.parse(call.body)
    payload["FromEmailAddress"].as_s.should eq("from@example.com")
    payload["Destination"]["ToAddresses"].as_a.map(&.as_s).should eq(["a@example.com", "b@example.com"])
    payload["ReplyToAddresses"].as_a.map(&.as_s).should eq(["reply@example.com"])
    simple = payload["Content"]["Simple"]
    simple["Subject"]["Data"].as_s.should eq("Subject")
    simple["Subject"]["Charset"].as_s.should eq("UTF-8")
    simple["Body"]["Text"]["Data"].as_s.should eq("Olá")
    simple["Body"]["Html"]["Data"].as_s.should eq("<p>Olá</p>")
  end

  it "omits html and reply_to when they are absent" do
    transport = FakeTransport.new
    ses_mailer(transport: transport).send(sample_mail)
    payload = JSON.parse(transport.calls[0].body)
    payload["Content"]["Simple"]["Body"]["Html"]?.should be_nil
    payload["ReplyToAddresses"]?.should be_nil
  end

  it "omits an empty html body" do
    transport = FakeTransport.new
    ses_mailer(transport: transport).send(sample_mail(html: ""))
    payload = JSON.parse(transport.calls[0].body)
    payload["Content"]["Simple"]["Body"]["Html"]?.should be_nil
  end

  it "signs the session token when it is set" do
    transport = FakeTransport.new
    ses_mailer(session_token: "session-token", transport: transport).send(sample_mail)
    transport.calls[0].headers["X-Amz-Security-Token"].should eq("session-token")
    transport.calls[0].headers["Authorization"].should contain("x-amz-security-token")
  end

  it "uses an explicit https port only when it is not 443" do
    transport = FakeTransport.new
    ses_mailer(endpoint: "https://email.sa-east-1.amazonaws.com:443/v2/email/outbound-emails", transport: transport).send(sample_mail)
    transport.calls[0].headers["Host"].should eq("email.sa-east-1.amazonaws.com")
  end

  it "omits the default http port from the host header" do
    transport = FakeTransport.new
    ses_mailer(endpoint: "http://127.0.0.1:80/v2/email/outbound-emails", transport: transport).send(sample_mail)
    transport.calls[0].headers["Host"].should eq("127.0.0.1")
  end

  it "includes a non-default port in the host header" do
    transport = FakeTransport.new
    ses_mailer(endpoint: "http://127.0.0.1:9/v2/email/outbound-emails", transport: transport).send(sample_mail)
    transport.calls[0].headers["Host"].should eq("127.0.0.1:9")
    transport.calls[0].uri.path.should eq("/v2/email/outbound-emails")
  end

  it "fills the SES path when the endpoint has none" do
    transport = FakeTransport.new
    ses_mailer(endpoint: "https://email.eu-west-1.amazonaws.com", transport: transport).send(sample_mail)
    transport.calls[0].uri.path.should eq("/v2/email/outbound-emails")
    transport.calls[0].headers["Host"].should eq("email.eu-west-1.amazonaws.com")
  end

  it "fills the SES path when the endpoint path is /" do
    transport = FakeTransport.new
    ses_mailer(endpoint: "https://email.eu-west-1.amazonaws.com/", transport: transport).send(sample_mail)
    transport.calls[0].uri.path.should eq("/v2/email/outbound-emails")
  end

  it "keeps a custom endpoint path" do
    transport = FakeTransport.new
    ses_mailer(endpoint: "https://vpce.example.com/custom", transport: transport).send(sample_mail)
    transport.calls[0].uri.path.should eq("/custom")
    transport.calls[0].headers["Host"].should eq("vpce.example.com")
  end

  it "returns MailError for an HTTP error and strips secrets" do
    transport = FakeTransport.new
    transport.status = 400
    transport.response_body = %({"message":"rejected secret-key AKIDEXAMPLE session-token"})
    result = ses_mailer(session_token: "session-token", transport: transport).send(sample_mail)
    error = mail_error(result)
    error.message.should eq("SES send failed (400): rejected [redacted] [redacted] [redacted]")
  end

  it "reads the Message field when message is absent" do
    transport = FakeTransport.new
    transport.status = 403
    transport.response_body = %({"Message":"nope"})
    mail_error(ses_mailer(transport: transport).send(sample_mail)).message.should eq("SES send failed (403): nope")
  end

  it "returns the status when the error body is empty" do
    transport = FakeTransport.new
    transport.status = 500
    transport.response_body = ""
    mail_error(ses_mailer(transport: transport).send(sample_mail)).message.should eq("SES send failed (500)")
  end

  it "returns the status when the error body is not JSON" do
    transport = FakeTransport.new
    transport.status = 502
    transport.response_body = "not-json"
    mail_error(ses_mailer(transport: transport).send(sample_mail)).message.should eq("SES send failed (502)")
  end

  it "returns the status when the error JSON is not an object" do
    transport = FakeTransport.new
    transport.status = 400
    transport.response_body = "[]"
    mail_error(ses_mailer(transport: transport).send(sample_mail)).message.should eq("SES send failed (400)")
  end

  it "returns the status when the error object has no message" do
    transport = FakeTransport.new
    transport.status = 400
    transport.response_body = %({"Code":"Rejected"})
    mail_error(ses_mailer(transport: transport).send(sample_mail)).message.should eq("SES send failed (400)")
  end

  it "returns the status when the message is not a string" do
    transport = FakeTransport.new
    transport.status = 400
    transport.response_body = %({"message":1})
    mail_error(ses_mailer(transport: transport).send(sample_mail)).message.should eq("SES send failed (400)")
  end

  it "returns MailError when the transport raises" do
    transport = FakeTransport.new
    transport.error = IO::Error.new("down")
    mail_error(ses_mailer(transport: transport).send(sample_mail)).message.should eq("mail send failed")
  end

  it "returns MailError when TLS fails" do
    transport = FakeTransport.new
    transport.error = OpenSSL::Error.new("tls")
    mail_error(ses_mailer(transport: transport).send(sample_mail)).message.should eq("mail send failed")
  end

  it "rejects an empty region" do
    expect_raises(ArgumentError, "region must not be empty") do
      ses_mailer(region: "")
    end
  end

  it "rejects an invalid region" do
    expect_raises(ArgumentError, "region is invalid") do
      ses_mailer(region: "SA-EAST-1")
    end
  end

  it "rejects an empty access key" do
    expect_raises(ArgumentError, "access_key_id must not be empty") do
      ses_mailer(access_key_id: "")
    end
  end

  it "rejects an empty secret" do
    expect_raises(ArgumentError, "secret_access_key must not be empty") do
      ses_mailer(secret_access_key: "")
    end
  end

  it "rejects an empty session token" do
    expect_raises(ArgumentError, "session_token must not be empty") do
      ses_mailer(session_token: "")
    end
  end

  it "rejects an empty endpoint" do
    expect_raises(ArgumentError, "endpoint must not be empty") do
      ses_mailer(endpoint: "")
    end
  end

  it "rejects an endpoint without a scheme" do
    expect_raises(ArgumentError, "endpoint scheme must be http or https") do
      ses_mailer(endpoint: "email.sa-east-1.amazonaws.com")
    end
  end

  it "rejects an endpoint scheme that is not http" do
    expect_raises(ArgumentError, "endpoint scheme must be http or https") do
      ses_mailer(endpoint: "ftp://example.com/path")
    end
  end

  it "rejects an endpoint without a host" do
    expect_raises(ArgumentError, "endpoint host must not be empty") do
      ses_mailer(endpoint: "http://")
    end
  end

  it "rejects endpoint userinfo" do
    expect_raises(ArgumentError, "endpoint userinfo is not supported") do
      ses_mailer(endpoint: "http://user:pass@example.com/path")
    end
  end

  it "rejects an endpoint query" do
    expect_raises(ArgumentError, "endpoint query is not supported") do
      ses_mailer(endpoint: "http://example.com/path?a=1")
    end
  end

  it "builds a mailer from ENV" do
    transport = FakeTransport.new
    with_env({
      "AWS_REGION"            => "eu-west-1",
      "AWS_ACCESS_KEY_ID"     => "AKIDENV",
      "AWS_SECRET_ACCESS_KEY" => "env-secret",
      "AWS_SESSION_TOKEN"     => nil,
    }) do
      mailer = Alumna::SES.from_env(transport: transport)
      mailer.send(sample_mail).should be_nil
    end
    transport.calls[0].headers["Host"].should eq("email.eu-west-1.amazonaws.com")
    transport.calls[0].headers["Authorization"].should contain("Credential=AKIDENV/")
    transport.calls[0].headers["X-Amz-Security-Token"]?.should be_nil
  end

  it "reads the session token from ENV" do
    transport = FakeTransport.new
    with_env({
      "AWS_REGION"            => "eu-west-1",
      "AWS_ACCESS_KEY_ID"     => "AKIDENV",
      "AWS_SECRET_ACCESS_KEY" => "env-secret",
      "AWS_SESSION_TOKEN"     => "env-token",
    }) do
      Alumna::SES.from_env(transport: transport).send(sample_mail).should be_nil
    end
    transport.calls[0].headers["X-Amz-Security-Token"].should eq("env-token")
  end

  it "rejects a missing AWS_REGION" do
    expect_raises(ArgumentError, "AWS_REGION must not be empty") do
      with_env({
        "AWS_REGION"            => nil,
        "AWS_ACCESS_KEY_ID"     => "AKIDENV",
        "AWS_SECRET_ACCESS_KEY" => "env-secret",
      }) do
        Alumna::SES.from_env
      end
    end
  end

  it "rejects an empty AWS_ACCESS_KEY_ID" do
    expect_raises(ArgumentError, "AWS_ACCESS_KEY_ID must not be empty") do
      with_env({
        "AWS_REGION"            => "eu-west-1",
        "AWS_ACCESS_KEY_ID"     => "",
        "AWS_SECRET_ACCESS_KEY" => "env-secret",
      }) do
        Alumna::SES.from_env
      end
    end
  end

  it "rejects an empty AWS_SECRET_ACCESS_KEY" do
    expect_raises(ArgumentError, "AWS_SECRET_ACCESS_KEY must not be empty") do
      with_env({
        "AWS_REGION"            => "eu-west-1",
        "AWS_ACCESS_KEY_ID"     => "AKIDENV",
        "AWS_SECRET_ACCESS_KEY" => "",
      }) do
        Alumna::SES.from_env
      end
    end
  end

  it "posts through HTTP::Client" do
    received = Channel({String, String}).new(1)
    server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      host = context.request.headers["Host"]? || ""
      context.response.status_code = 200
      context.response.content_type = "application/json"
      context.response.print %({"MessageId":"local-1"})
      received.send({host, body})
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    begin
      wait_for_port(address.port)
      mailer = Alumna::SES.new(
        region: "sa-east-1",
        access_key_id: "AKIDEXAMPLE",
        secret_access_key: "secret-key",
        endpoint: "http://127.0.0.1:#{address.port}/v2/email/outbound-emails",
      )
      mailer.send(sample_mail).should be_nil
      host, body = received.receive
      host.should eq("127.0.0.1:#{address.port}")
      JSON.parse(body)["FromEmailAddress"].as_s.should eq("from@example.com")
    ensure
      server.close
    end
  end

  it "records concurrent sends" do
    transport = FakeTransport.new
    mailer = ses_mailer(transport: transport)
    WaitGroup.wait do |wg|
      8.times do
        wg.spawn { mailer.send(sample_mail) }
      end
    end
    transport.calls.size.should eq(8)
  end
end

describe "live Amazon SES" do
  it "sends when AWS_SES_LIVE=1" do
    unless ENV["AWS_SES_LIVE"]? == "1"
      pending! "Set AWS_SES_LIVE=1 to call Amazon"
    end
    from = ENV["AWS_SES_FROM"]?
    pending!("Set AWS_SES_FROM") unless from
    to = ENV["AWS_SES_TO"]?
    pending!("Set AWS_SES_TO") unless to
    mailer = Alumna::SES.from_env
    result = mailer.send(Alumna::Mail.new(from: from, to: to, subject: "Alumna SES live", text: "Live send"))
    result.should be_nil
  end
end
