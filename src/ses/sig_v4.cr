require "digest/sha256"
require "openssl"
require "uri"

# Signs one AWS request with Signature Version 4.
# SES#send uses this for SendEmail. Application code does not call it.
#
# Header names are lowercased. Header values are trimmed.
# x-amz-content-sha256 is the SHA256 hex digest of the body.
# The query string is empty.
#
# Canonical headers already end with a newline.
# The canonical request writes one more newline before the signed header names.
#
# A module, not a struct: it has only class methods. A struct adds a
# constructor that nothing calls, and `crystal tool unreachable` reports it.
module Alumna::SES::SigV4
  def self.sign(
    *,
    method : String,
    path : String,
    signed_headers : Array({String, String}),
    body : String,
    region : String,
    service : String,
    access_key_id : String,
    secret_access_key : String,
  ) : NamedTuple(authorization: String, payload_hash: String)
    payload_hash = Digest::SHA256.hexdigest(body)
    pairs = [] of {String, String}
    signed_headers.each do |pair|
      pairs << {pair[0].downcase, pair[1].strip}
    end
    pairs.reject! { |pair| pair[0] == "x-amz-content-sha256" }
    pairs << {"x-amz-content-sha256", payload_hash}
    pairs.sort!

    date_pair = pairs.find { |pair| pair[0] == "x-amz-date" }
    raise ArgumentError.new("x-amz-date is required") unless date_pair
    amz_date = date_pair[1]
    date_stamp = amz_date[0, 8]

    signed_names = String.build do |io|
      pairs.each_with_index do |pair, index|
        io << ';' if index > 0
        io << pair[0]
      end
    end

    canonical = String.build do |io|
      io << method.upcase << '\n'
      io << URI.encode_path(path) << '\n'
      io << '\n'
      pairs.each do |pair|
        io << pair[0] << ':' << pair[1] << '\n'
      end
      io << '\n'
      io << signed_names << '\n'
      io << payload_hash
    end

    scope = "#{date_stamp}/#{region}/#{service}/aws4_request"
    string_to_sign = String.build do |io|
      io << "AWS4-HMAC-SHA256\n"
      io << amz_date << '\n'
      io << scope << '\n'
      io << Digest::SHA256.hexdigest(canonical)
    end

    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, signing_key(secret_access_key, date_stamp, region, service), string_to_sign)
    authorization = String.build do |io|
      io << "AWS4-HMAC-SHA256 Credential=" << access_key_id << '/' << scope
      io << ", SignedHeaders=" << signed_names
      io << ", Signature=" << signature
    end
    {authorization: authorization, payload_hash: payload_hash}
  end

  private def self.signing_key(secret : String, date_stamp : String, region : String, service : String) : Bytes
    k_date = hmac("AWS4#{secret}", date_stamp)
    k_region = hmac(k_date, region)
    k_service = hmac(k_region, service)
    hmac(k_service, "aws4_request")
  end

  private def self.hmac(key : String | Bytes, data : String) : Bytes
    OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, key, data)
  end
end
