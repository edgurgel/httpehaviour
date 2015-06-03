defmodule HTTPehaviour do
  @moduledoc """
  The HTTP client for Elixir.
  """

  @type headers :: [{binary, binary}]

  @doc """
  Start httpehaviour and dependencies.
  """
  def start, do: :application.ensure_all_started(:httpehaviour)

  defmodule Request do
    defstruct method: nil, url: nil, body: nil, headers: []
    @type t :: %Request{ method: nil, url: binary, body: binary, headers: HTTPehaviour.headers }
  end

  defmodule Response do
    defstruct status_code: nil, body: nil, headers: [], state: nil
    @type t :: %Response{ status_code: integer, body: binary, headers: HTTPehaviour.headers, state: any }
  end

  defmodule AsyncResponse do
    defstruct id: nil
    @type t :: %AsyncResponse { id: reference }
  end

  defmodule AsyncStatus do
    defstruct id: nil, status_code: nil
    @type t :: %AsyncStatus { id: reference, status_code: integer }
  end

  defmodule AsyncHeaders do
    defstruct id: nil, headers: []
    @type t :: %AsyncHeaders { id: reference, headers: HTTPehaviour.headers }
  end

  defmodule AsyncChunk do
    defstruct id: nil, chunk: nil
    @type t :: %AsyncChunk { id: reference, chunk: binary }
  end

  defmodule AsyncEnd do
    defstruct id: nil, state: nil
    @type t :: %AsyncEnd { id: reference, state: any }
  end

  defmodule Error do
    defexception reason: nil, id: nil, state: nil
    @type t :: %Error { id: reference, reason: any, state: any }

    def message(%Error{reason: reason, id: nil}), do: inspect(reason)
    def message(%Error{reason: reason, id: id}), do: "[Reference: #{id}] - #{inspect reason}"
  end

  @spec get(binary, headers, [{atom, any}]) :: {:ok, Response.t | AsyncResponse.t} | {:error, Error.t}
  def get(url, headers \\ [], options \\ []),          do: request(:get, url, "", headers, options)

  @spec get!(binary, headers, [{atom, any}]) :: Response.t | AsyncResponse.t
  def get!(url, headers \\ [], options \\ []),         do: request!(:get, url, "", headers, options)

  @spec put(binary, binary, headers, [{atom, any}]) :: {:ok, Response.t | AsyncResponse.t } | {:error, Error.t}
  def put(url, body, headers \\ [], options \\ []),    do: request(:put, url, body, headers, options)

  @spec put!(binary, binary, headers, [{atom, any}]) :: Response.t | AsyncResponse.t
  def put!(url, body, headers \\ [], options \\ []),   do: request!(:put, url, body, headers, options)

  @spec head(binary, headers, [{atom, any}]) :: {:ok, Response.t | AsyncResponse.t} | {:error, Error.t}
  def head(url, headers \\ [], options \\ []),         do: request(:head, url, "", headers, options)

  @spec head!(binary, headers, [{atom, any}]) :: Response.t | AsyncResponse.t
  def head!(url, headers \\ [], options \\ []),        do: request!(:head, url, "", headers, options)

  @spec post(binary, binary, headers, [{atom, any}]) :: {:ok, Response.t | AsyncResponse.t} | {:error, Error.t}
  def post(url, body, headers \\ [], options \\ []),   do: request(:post, url, body, headers, options)

  @spec post!(binary, binary, headers, [{atom, any}]) :: Response.t | AsyncResponse.t
  def post!(url, body, headers \\ [], options \\ []),  do: request!(:post, url, body, headers, options)

  @spec patch(binary, binary, headers, [{atom, any}]) :: {:ok, Response.t | AsyncResponse.t} | {:error, Error.t}
  def patch(url, body, headers \\ [], options \\ []),  do: request(:patch, url, body, headers, options)

  @spec patch!(binary, binary, headers, [{atom, any}]) :: Response.t | AsyncResponse.t
  def patch!(url, body, headers \\ [], options \\ []), do: request!(:patch, url, body, headers, options)

  @spec delete(binary, headers, [{atom, any}]) :: {:ok, Response.t | AsyncResponse.t} | {:error, Error.t}
  def delete(url, headers \\ [], options \\ []),       do: request(:delete, url, "", headers, options)

  @spec delete!(binary, headers, [{atom, any}]) :: Response.t | AsyncResponse.t
  def delete!(url, headers \\ [], options \\ []),      do: request!(:delete, url, "", headers, options)

  @spec options(binary, headers, [{atom, any}]) :: {:ok, Response.t | AsyncResponse.t} | {:error, Error.t}
  def options(url, headers \\ [], options \\ []),      do: request(:options, url, "", headers, options)

  @spec options!(binary, headers, [{atom, any}]) :: Response.t | AsyncResponse.t
  def options!(url, headers \\ [], options \\ []),     do: request!(:options, url, "", headers, options)


  @spec request!(atom, binary, binary, headers, [{atom, any}]) :: Response.t
  def request!(method, url, body \\ "", headers \\ [], options \\ []) do
    case request(method, url, body, headers, options) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end

  @spec request(atom, binary, binary, headers, [{atom, any}]) :: {:ok, Response.t | AsyncResponse.t}
    | {:error, Error.t}
  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    if Keyword.has_key?(options, :params) do
      url = url <> "?" <> URI.encode_query(options[:params])
    end

    behaviour = Keyword.get options, :behaviour, nil
    state     = nil

    try do
      if behaviour do
        { url, headers, body, state } = init_state(method, url, headers, body, behaviour)
      end
      hn_options = build_hackney_options(options, behaviour, state)
      case do_request(method, to_string(url), headers, body, hn_options) do
        { :ok, status_code, headers, _client } when status_code in [204, 304] ->
          response(status_code, headers, "", behaviour, state)
        { :ok, status_code, headers } -> response(status_code, headers, "", behaviour, state)
        { :ok, status_code, headers, client } ->
          case :hackney.body(client) do
            { :ok, body } -> response(status_code, headers, body, behaviour, state)
            { :error, reason } -> { :error, %Error { reason: reason, state: state } }
          end
        { :ok, id } -> { :ok, %AsyncResponse { id: id } }
        { :error, reason } -> { :error, %Error { reason: reason, state: state } }
       end
    catch
      { :halt, state } -> { :error, %Error { reason: :halted, state: state } }
    end
  end

  defp init_state(_method, _url, _headers, _body, nil), do: nil

  defp init_state(method, url, headers, body, behaviour) when is_atom(behaviour) do
    { :continue, state } = behaviour.init_request(%Request { method: method, url: url, headers: headers, body: body }) |> continue_or_halt
    { :continue, url, state } = behaviour.process_request_url(url, state) |> continue_or_halt
    { :continue, headers, state } = behaviour.process_request_headers(headers, state) |> continue_or_halt
    { :continue, body, state } = behaviour.process_request_body(body, state) |> continue_or_halt
    { url, headers, body, state }
  end

  defp continue_or_halt({ :halt, _ } = it), do: throw it
  defp continue_or_halt(it), do: it

  defp do_request(method, url, headers, body, hn_options) do
    if is_map(headers) do
      headers = Enum.into(headers, [])
    end
    :hackney.request(method, url, headers, body, hn_options)
  end

  defp build_hackney_options(options, behaviour, state) do
    timeout = Keyword.get options, :timeout
    recv_timeout = Keyword.get options, :recv_timeout
    stream_to = Keyword.get options, :stream_to
    proxy = Keyword.get options, :proxy
    proxy_auth = Keyword.get options, :proxy_auth

    hn_options = Keyword.get options, :hackney, []

    if timeout, do: hn_options = [{:connect_timeout, timeout} | hn_options]
    if recv_timeout, do: hn_options = [{:recv_timeout, recv_timeout} | hn_options]
    if proxy, do: hn_options = [{:proxy, proxy} | hn_options]
    if proxy_auth, do: hn_options = [{:proxy_auth, proxy_auth} | hn_options]

    if stream_to do
      { :ok, pid } = HTTPehaviour.Transformer.start_link([stream_to, behaviour, state])
      hn_options = [:async, { :stream_to, pid } | hn_options]
    end

    hn_options
  end

  defp response(status_code, headers, body, nil, _) do
    { :ok, %Response { status_code: status_code, headers: headers, body: body } }
  end

  defp response(status_code, headers, body, behaviour, state) when is_atom(behaviour) do
    { :continue, status_code, state } = behaviour.process_response_status_code(status_code, state) |> continue_or_halt
    { :continue, headers, state } = behaviour.process_response_headers(headers, state) |> continue_or_halt
    { :continue, body, state } = behaviour.process_response_body(body, state) |> continue_or_halt
    state = behaviour.terminate_request(state)
    { :ok, %Response { status_code: status_code, headers: headers, body: body, state: state } }
  end
end
