require "../spec_helper"

# Fixed test vector, shared by every SDK in the family (see manza-ruby's
# spec/manza/transfer_authorization_spec.rb). Each signer must produce
# exactly these hex digests from these inputs. Computed independently:
#
#   printf '%s' '<input>' | openssl dgst -sha256 -hmac 'whsec_test_vector_secret'
#
# `transfer_method` is a required named argument (nil included), so a v1
# call without it fails to compile here instead of failing as a signature
# attempt at the API, where five of them fail the challenge.
describe Manza::TransferAuthorization do
  secret = "whsec_test_vector_secret"
  payment_id = "0199a1b2-0000-7000-8000-000000000001"
  nonce = "n0nce-0123456789abcdef"
  account_id = "0199a1b2-0000-7000-8000-000000000002"

  it "signs version v2" do
    Manza::TransferAuthorization::SIGNATURE_VERSION.should eq("manza.transfer-authorization.v2")
  end

  describe "external-account payee with a client_reference and a transfer_method" do
    input = Manza::TransferAuthorization.signature_input(
      payment_id, nonce, "2500.0", "MAD", account_id,
      Manza::TransferAuthorization.payee_for(external_account_id: "0199a1b2-0000-7000-8000-000000000003"),
      "po_1", transfer_method: "eft"
    )

    it "builds the versioned, pipe-joined signature input with the transfer_method last" do
      input.should eq(
        "manza.transfer-authorization.v2|0199a1b2-0000-7000-8000-000000000001|n0nce-0123456789abcdef|" \
        "2500.0|MAD|0199a1b2-0000-7000-8000-000000000002|ext:0199a1b2-0000-7000-8000-000000000003|po_1|eft"
      )
    end

    it "signs it to the shared vector" do
      Manza::TransferAuthorization.sign(secret, input)
        .should eq("904da7d0b73b2c919ffa1ae64d262ce5825ee4d2c8420fd70a3d257353e6c43a")
    end
  end

  describe "a nil transfer_method" do
    input = Manza::TransferAuthorization.signature_input(
      payment_id, nonce, "2500.0", "MAD", account_id,
      Manza::TransferAuthorization.payee_for(external_account_id: "0199a1b2-0000-7000-8000-000000000003"),
      "po_1", transfer_method: nil
    )

    it "ends with an empty transfer_method segment" do
      input.should end_with("|ext:0199a1b2-0000-7000-8000-000000000003|po_1|")
    end

    it "signs it to the shared vector" do
      Manza::TransferAuthorization.sign(secret, input)
        .should eq("029dd12924a846d7af2f4aecb61e4f4f9bd64d37315230864fb03917adc29edf")
    end
  end

  describe "own-account payee without a client_reference or a transfer_method" do
    input = Manza::TransferAuthorization.signature_input(
      payment_id, nonce, "2500.0", "MAD", account_id,
      Manza::TransferAuthorization.payee_for(destination_account_id: "0199a1b2-0000-7000-8000-000000000004"),
      transfer_method: nil
    )

    it "ends with two empty segments" do
      input.should end_with("|own:0199a1b2-0000-7000-8000-000000000004||")
    end

    it "signs it to the shared vector" do
      Manza::TransferAuthorization.sign(secret, input)
        .should eq("a21ccf43b94f23d7a595a36bd788c27c7adbc5686a5ad4427b22d9957568c9fb")
    end
  end

  describe ".payee_for" do
    it "refuses both ids at once" do
      expect_raises(Manza::ArgumentError, /exactly one/) do
        Manza::TransferAuthorization.payee_for(external_account_id: "a", destination_account_id: "b")
      end
    end

    it "refuses neither id" do
      expect_raises(Manza::ArgumentError, /exactly one/) do
        Manza::TransferAuthorization.payee_for
      end
    end
  end
end
