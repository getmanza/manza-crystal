module Manza
  module Resources
    # Deprecated: use `Payments` (`client.payments`). Kept for all of 1.x;
    # it is the same class and calls `/api/payments`.
    alias TransferDrafts = Payments
  end
end
