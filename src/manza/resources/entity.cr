module Manza
  module Resources
    # The current entity (the tenant the API key belongs to).
    class Entity < Base
      # GET /api/entity
      def get : Response
        http_get("api/entity")
      end
    end
  end
end
