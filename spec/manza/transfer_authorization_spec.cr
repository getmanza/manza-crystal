require "../spec_helper"

# Fixed test vector, shared by every SDK in the family (see manza-ruby's
# spec/manza/transfer_authorization_spec.rb). Each signer must produce
# exactly these hex digests from these inputs. Computed independently:
#
#   printf '%s' '<input>' | openssl dgst -sha256 -hmac 'whsec_test_vector_secret'
describe Manza::TransferAuthorization do
  secret = "whsec_test_vector_secret"
  payment_id = "0199a1b2-0000-7000-8000-000000000001"
  nonce = "n0nce-0123456789abcdef"
  account_id = "0199a1b2-0000-7000-8000-000000000002"

  describe "external-account payee with a client_reference" do
    input = Manza::TransferAuthorization.signature_input(
      payment_id, nonce, "2500.0", "MAD", account_id,
      Manza::TransferAuthorization.payee_for(external_account_id: "0199a1b2-0000-7000-8000-000000000003"),
      "po_1"
    )

    it "builds the versioned, pipe-joined signature input" do
      input.should eq(
        "manza.transfer-authorization.v1|0199a1b2-0000-7000-8000-000000000001|n0nce-0123456789abcdef|" \
        "2500.0|MAD|0199a1b2-0000-7000-8000-000000000002|ext:0199a1b2-0000-7000-8000-000000000003|po_1"
      )
    end

    it "signs it to the shared vector" do
      Manza::TransferAuthorization.sign(secret, input)
        .should eq("6e8eaec0f89a4eb3b22df1133b3d6dfebfa8505c34c58ed0ff192516e4223078")
    end
  end

  describe "own-account payee without a client_reference" do
    input = Manza::TransferAuthorization.signature_input(
      payment_id, nonce, "2500.0", "MAD", account_id,
      Manza::TransferAuthorization.payee_for(destination_account_id: "0199a1b2-0000-7000-8000-000000000004")
    )

    it "ends with an empty client_reference segment" do
      input.should end_with("|own:0199a1b2-0000-7000-8000-000000000004|")
    end

    it "signs it to the shared vector" do
      Manza::TransferAuthorization.sign(secret, input)
        .should eq("af9440b1de1bebb51f381ce43e3d0d27b6a4ccb99dcd548c0b5435ff4fdd1895")
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
