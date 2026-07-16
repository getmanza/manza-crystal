module Zazu
  # One page of a cursor-paginated list endpoint:
  # `{ "data": [...], "has_more": bool, "next_cursor": string|null }`.
  class Page
    # The API's hard page-size cap.
    MAX_PER_PAGE = 100

    # The records on this page, as-is from the API.
    getter data : Array(JSON::Any)

    # Whether more pages exist after this one.
    getter has_more : Bool

    # Cursor for the following page, when `has_more`.
    getter next_cursor : String?

    # The underlying API response.
    getter response : Response

    def initialize(@response : Response, @fetcher : Proc(String?, Page))
      body = @response.body.as_h? || {} of String => JSON::Any
      @data = body["data"]?.try(&.as_a?) || [] of JSON::Any
      @has_more = body["has_more"]?.try(&.as_bool?) || false
      @next_cursor = body["next_cursor"]?.try(&.as_s?)
    end

    # Fetches the following page, or returns `nil` when this is the
    # last one.
    def next : Page?
      cursor = next_cursor
      return nil unless has_more && cursor
      @fetcher.call(cursor)
    end
  end
end
