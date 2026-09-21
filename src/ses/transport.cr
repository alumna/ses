require "http/client"

# Posts one signed request.
# Specs pass a fake. The default uses HTTP::Client.
# Default CI does not call Amazon.
abstract class Alumna::SES::Transport
  abstract def post(uri : URI, headers : HTTP::Headers, body : String) : {Int32, String}
end

class Alumna::SES::HTTPTransport < Alumna::SES::Transport
  def post(uri : URI, headers : HTTP::Headers, body : String) : {Int32, String}
    HTTP::Client.new(uri) do |client|
      response = client.post(uri.request_target, headers: headers, body: body)
      {response.status_code, response.body}
    end
  end
end
