require "./spec_helper"

describe Alumna::SES::SigV4 do
  it "matches the AWS Signature Version 4 example" do
    signed = Alumna::SES::SigV4.sign(
      method: "GET",
      path: "/test.txt",
      signed_headers: [
        {"Host", "examplebucket.s3.amazonaws.com"},
        {"X-Amz-Date", "20130524T000000Z"},
        {"Range", "bytes=0-9"},
      ],
      body: "",
      region: "us-east-1",
      service: "s3",
      access_key_id: "AKIAIOSFODNN7EXAMPLE",
      secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    )
    signed[:payload_hash].should eq("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    signed[:authorization].should eq(
      "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, " \
      "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, " \
      "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
    )
  end

  it "trims header values before signing" do
    plain = Alumna::SES::SigV4.sign(
      method: "GET",
      path: "/",
      signed_headers: [
        {"host", "example.com"},
        {"x-amz-date", "20130524T000000Z"},
      ],
      body: "a",
      region: "us-east-1",
      service: "ses",
      access_key_id: "AKID",
      secret_access_key: "secret",
    )
    spaced = Alumna::SES::SigV4.sign(
      method: "get",
      path: "/",
      signed_headers: [
        {"host", " example.com "},
        {"x-amz-date", "20130524T000000Z"},
      ],
      body: "a",
      region: "us-east-1",
      service: "ses",
      access_key_id: "AKID",
      secret_access_key: "secret",
    )
    spaced[:authorization].should eq(plain[:authorization])
  end

  it "rejects a request without x-amz-date" do
    expect_raises(ArgumentError, "x-amz-date is required") do
      Alumna::SES::SigV4.sign(
        method: "POST",
        path: "/",
        signed_headers: [{"host", "example.com"}],
        body: "",
        region: "us-east-1",
        service: "ses",
        access_key_id: "AKID",
        secret_access_key: "secret",
      )
    end
  end
end
