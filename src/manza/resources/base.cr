module Manza
  module Resources
    # Shared scaffolding for every resource. Carries a back-reference
    # to the client and exposes thin HTTP helpers that delegate to
    # `Manza::Client#request`.
    #
    # The helpers are `http_get`, `http_post`, etc. rather than
    # `get`/`post` so they do not shadow the public methods on resource
    # subclasses (resources commonly define a public `get(id)`).
    abstract class Base
      MAX_PER_PAGE = Page::MAX_PER_PAGE

      def initialize(@client : Client)
      end

      private getter client

      private def http_get(path : String, params : URI::Params? = nil) : Response
        client.get(path, params)
      end

      private def http_post(path : String, body : String? = nil) : Response
        client.post(path, body)
      end

      private def http_patch(path : String, body : String? = nil) : Response
        client.patch(path, body)
      end

      private def http_delete(path : String) : Response
        client.delete(path)
      end

      # Builds a paginated list. `path` is the collection endpoint;
      # `filters` holds the endpoint-specific query params (nil values
      # are dropped). `limit` is validated against MAX_PER_PAGE.
      private def list_page(path : String, limit : Int32, cursor : String?,
                            filters : Hash(String, String?) = {} of String => String?) : Page
        validated = validate_limit!(limit)
        fetch_list_page(path, validated, cursor, filters)
      end

      private def fetch_list_page(path : String, limit : Int32, cursor : String?,
                                  filters : Hash(String, String?)) : Page
        params = URI::Params.new
        filters.each do |key, value|
          params[key] = value if value
        end
        params["limit"] = limit.to_s
        if value = cursor
          params["cursor"] = value
        end

        response = http_get(path, params)
        Page.new(response, ->(next_cursor : String?) { fetch_list_page(path, limit, next_cursor, filters) })
      end

      private def validate_limit!(limit : Int32) : Int32
        unless limit.positive?
          raise Manza::ArgumentError.new("limit must be a positive integer (got #{limit})")
        end
        if limit > MAX_PER_PAGE
          raise Manza::ArgumentError.new("limit cannot exceed #{MAX_PER_PAGE} (got #{limit})")
        end

        limit
      end

      # Builds a request path by joining a literal base path with one
      # or more dynamic segments. The base is appended verbatim; each
      # dynamic segment is percent-encoded so an ID containing `/` or
      # other special characters cannot escape the intended path.
      private def encode_path(base : String, *segments) : String
        encoded = segments.map do |segment|
          str = segment.to_s
          # An empty segment would silently turn `/things/:id` into
          # `/things/`, which on most APIs redispatches to the list
          # endpoint. Surface it loudly.
          raise Manza::ArgumentError.new("path segment cannot be blank") if str.empty?

          URI.encode_path_segment(str)
        end
        ([base] + encoded.to_a).join('/')
      end
    end
  end
end
