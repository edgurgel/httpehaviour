defmodule HTTPehaviour.Client do
  use Behaviour

  defcallback init_request(request :: HTTPehaviour.Request.t) :: { :continue, any } | { :halt, any }

  defcallback process_request_url(url :: binary, state :: any) :: { :continue, binary, any } | { :halt, any }
  defcallback process_request_body(body :: binary, state :: any) :: { :continue, binary, any } | { :halt, any }
  defcallback process_request_headers(headers :: HTTPehaviour.headers, state :: any) :: { :continue, HTTPehaviour.headers, any } | { :halt, any }

  defcallback process_response_status_code(status_code :: integer, state :: any) :: { :continue, integer, any } | { :halt, any }
  defcallback process_response_headers(headers :: HTTPehaviour.headers, state :: any) :: { :continue, HTTPehaviour.headers, any } | { :halt, any }
  defcallback process_response_body(body :: binary, state :: any) :: { :continue, binary, any } | { :halt, any }
  defcallback process_response_chunk(chunk :: binary, state :: any) :: { :continue, binary, any } | { :halt, any }

  defcallback terminate_request(state :: any) :: any

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour HTTPehaviour.Client
      import HTTPehaviour

      @doc false
      def init_request(args), do: { :continue, args }

      def process_request_url(url, state), do: { :continue, url, state }
      def process_request_body(body, state), do: { :continue, body, state }
      def process_request_headers(headers, state), do: { :continue, headers, state }

      def process_response_status_code(status_code, state), do: { :continue, status_code, state }
      def process_response_headers(headers, state), do: { :continue, headers, state }
      def process_response_body(body, state), do: { :continue, body, state }
      def process_response_chunk(chunk, state), do: { :continue, chunk, state }

      def terminate_request(state), do: state

      defoverridable [init_request: 1, process_request_url: 2, process_request_body: 2, process_request_headers: 2,
        process_response_status_code: 2, process_response_headers: 2, process_response_body: 2,
        process_response_chunk: 2, terminate_request: 1]
    end
  end
end
