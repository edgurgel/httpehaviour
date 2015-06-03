defmodule HTTPehaviourTest do
  use ExUnit.Case
  import PathHelpers
  import :meck

  setup do
    on_exit fn -> unload end
    :ok
  end

  defmodule MyClient do
    use HTTPehaviour.Client

    def init_request(_args), do: { :continue, [:init_request] }

    def process_request_url(url, state), do: { :continue, url, [:process_request_url | state] }
    def process_request_body(body, state), do: { :continue, body, [:process_request_body | state] }
    def process_request_headers(headers, state), do: { :continue, headers, [:process_request_headers | state] }

    def process_response_status_code(status_code, state), do: { :continue, status_code, [:process_response_status_code | state] }
    def process_response_headers(headers, state), do: { :continue, headers, [:process_response_headers | state] }
    def process_response_body(body, state), do: { :continue, body, [:process_response_body | state] }
    def process_response_chunk(chunk, state), do: { :continue, chunk, [:process_response_chunk | state] }

    def terminate_request(state), do: [:terminate_request | state]
  end

  defmodule DefaultClient do
    use HTTPehaviour.Client
  end

  test "request using default" do
    response = HTTPehaviour.get!("localhost:8080/get", [], behaviour: DefaultClient)

    request = %HTTPehaviour.Request{body: "", headers: [], method: :get, url: "localhost:8080/get"}
    assert response.state == request
    assert response.status_code == 200
  end

  test "request using custom Client" do
    response = HTTPehaviour.get!("localhost:8080/get", [], behaviour: MyClient)

    path = [:terminate_request, :process_response_body, :process_response_headers, :process_response_status_code, :process_request_body,
            :process_request_headers, :process_request_url, :init_request]
    assert(response.state == path)
  end

  test "asynchronous request using Client" do
    path = [:terminate_request, :process_response_chunk, :process_response_headers, :process_response_status_code, :process_request_body,
            :process_request_headers, :process_request_url, :init_request]

    {:ok, %HTTPehaviour.AsyncResponse{id: id}} = HTTPehaviour.get "localhost:8080/get", [], [behaviour: MyClient, stream_to: self]

    assert_receive %HTTPehaviour.AsyncStatus{ id: ^id, status_code: 200 }, 1_000
    assert_receive %HTTPehaviour.AsyncHeaders{ id: ^id, headers: headers }, 1_000
    assert_receive %HTTPehaviour.AsyncChunk{ id: ^id, chunk: _chunk }, 1_000
    assert_receive %HTTPehaviour.AsyncEnd{ id: ^id, state: ^path }, 1_000
    assert is_list(headers)
  end

  test "get" do
    assert_response HTTPehaviour.get("localhost:8080/deny"), fn(response) ->
      assert :erlang.size(response.body) == 197
    end
  end

  test "get with params" do
    resp = HTTPehaviour.get("localhost:8080/get", [], params: %{foo: "bar", baz: "bong"})
    assert_response resp, fn(response) ->
      args = JSX.decode!(response.body)["args"]
      assert args["foo"] == "bar"
      assert args["baz"] == "bong"
      assert (args |> Dict.keys |> length) == 2
    end
  end

  test "head" do
    assert_response HTTPehaviour.head("localhost:8080/get"), fn(response) ->
      assert response.body == ""
    end
  end

  test "post charlist body" do
    assert_response HTTPehaviour.post("localhost:8080/post", 'test')
  end

  test "post binary body" do
    { :ok, file } = File.read(fixture_path("image.png"))

    assert_response HTTPehaviour.post("localhost:8080/post", file)
  end

  test "post form data" do
    assert_response HTTPehaviour.post("localhost:8080/post", {:form, [key: "value"]}, %{"Content-type" => "application/x-www-form-urlencoded"}), fn(response) ->
      Regex.match?(~r/"key".*"value"/, response.body)
    end
  end

  test "put" do
    assert_response HTTPehaviour.put("localhost:8080/put", "test")
  end

  test "patch" do
    assert_response HTTPehaviour.patch("localhost:8080/patch", "test")
  end

  test "delete" do
    assert_response HTTPehaviour.delete("localhost:8080/delete")
  end

  test "options" do
    assert_response HTTPehaviour.options("localhost:8080/get"), fn(response) ->
      assert get_header(response.headers, "content-length") == "0"
      assert is_binary(get_header(response.headers, "allow"))
    end
  end

  test "hackney option follow redirect absolute url" do
    hackney = [follow_redirect: true]
    assert_response HTTPehaviour.get("http://localhost:8080/redirect-to?url=http%3A%2F%2Flocalhost:8080%2Fget", [], [ hackney: hackney ])
  end

  test "hackney option follow redirect relative url" do
    hackney = [follow_redirect: true]
    assert_response HTTPehaviour.get("http://localhost:8080/relative-redirect/1", [], [ hackney: hackney ])
  end

  test "basic_auth hackney option" do
    hackney = [basic_auth: {"user", "pass"}]
    assert_response HTTPehaviour.get("http://localhost:8080/basic-auth/user/pass", [], [ hackney: hackney ])
  end

  test "explicit http scheme" do
    assert_response HTTPehaviour.head("http://localhost:8080/get")
  end

  test "https scheme" do
    assert_response HTTPehaviour.head("https://localhost:8433/get", [], [ hackney: [:insecure]])
  end

  test "char list URL" do
    assert_response HTTPehaviour.head('localhost:8080/get')
  end

  test "request headers as a map" do
    map_header = %{"X-Header" => "X-Value"}
    assert HTTPehaviour.get!("localhost:8080/get", map_header).body =~ "X-Value"
  end

  test "cached request" do
    if_modified = %{"If-Modified-Since" => "Tue, 11 Dec 2012 10:10:24 GMT"}
    response = HTTPehaviour.get!("localhost:8080/cache", if_modified)
    assert %HTTPehaviour.Response{status_code: 304, body: ""} = response
  end

  test "send cookies" do
    response = HTTPehaviour.get!("localhost:8080/cookies", %{}, hackney: [cookie: [{"SESSION", "123"}]])
    assert response.body =~ ~r(\"SESSION\".*\"123\")
  end

  test "exception" do
    assert HTTPehaviour.get "localhost:9999" == {:error, %HTTPehaviour.Error{reason: :econnrefused}}
    assert_raise HTTPehaviour.Error, ":econnrefused", fn ->
      HTTPehaviour.get! "localhost:9999"
    end
  end

  test "asynchronous request" do
    {:ok, %HTTPehaviour.AsyncResponse{id: id}} = HTTPehaviour.get "localhost:8080/get", [], [stream_to: self]

    assert_receive %HTTPehaviour.AsyncStatus{ id: ^id, status_code: 200 }, 1_000
    assert_receive %HTTPehaviour.AsyncHeaders{ id: ^id, headers: headers }, 1_000
    assert_receive %HTTPehaviour.AsyncChunk{ id: ^id, chunk: _chunk }, 1_000
    assert_receive %HTTPehaviour.AsyncEnd{ id: ^id }, 1_000
    assert is_list(headers)
  end

  test "request raises error tuple" do
    reason = {:closed, "Something happened"}
    expect(:hackney, :request, 5, {:error, reason})

    assert_raise HTTPehaviour.Error, "{:closed, \"Something happened\"}", fn ->
      HTTPehaviour.get!("http://localhost")
    end

    assert HTTPehaviour.get("http://localhost") == {:error, %HTTPehaviour.Error{reason: reason}}

    assert validate :hackney
  end

  test "passing connect_timeout option" do
    expect(:hackney, :request, [:post, "localhost", [], "body", [connect_timeout: 12345]],
                               { :ok, 200, "headers", :client })
    expect(:hackney, :body, 1, {:ok, "response"})

    assert HTTPehaviour.post!("localhost", "body", [], timeout: 12345) ==
    %HTTPehaviour.Response{ status_code: 200,
                            headers: "headers",
                            body: "response" }

    assert validate :hackney
  end

  test "passing recv_timeout option" do
    expect(:hackney, :request, [{[:post, "localhost", [], "body", [recv_timeout: 12345]],
                                 {:ok, 200, "headers", :client}}])
    expect(:hackney, :body, 1, {:ok, "response"})

    assert HTTPehaviour.post!("localhost", "body", [], recv_timeout: 12345) ==
    %HTTPehaviour.Response{ status_code: 200,
                            headers: "headers",
                            body: "response" }

    assert validate :hackney
  end

  test "passing proxy option" do
    expect(:hackney, :request, [{[:post, "localhost", [], "body", [proxy: "proxy"]],
                                 {:ok, 200, "headers", :client}}])
    expect(:hackney, :body, 1, {:ok, "response"})

    assert HTTPehaviour.post!("localhost", "body", [], proxy: "proxy") ==
    %HTTPehaviour.Response{ status_code: 200,
                            headers: "headers",
                            body: "response" }

    assert validate :hackney
  end

  test "passing proxy option with proxy_auth" do
    expect(:hackney, :request, [{[:post, "localhost", [], "body", [proxy_auth: {"username", "password"}, proxy: "proxy"]],
                                 {:ok, 200, "headers", :client}}])
    expect(:hackney, :body, 1, {:ok, "response"})

    assert HTTPehaviour.post!("localhost", "body", [], [proxy: "proxy", proxy_auth: {"username", "password"}]) ==
    %HTTPehaviour.Response{ status_code: 200,
                            headers: "headers",
                            body: "response" }

    assert validate :hackney
  end

  defp assert_response({:ok, response}, function \\ nil) do
    assert is_list(response.headers)
    assert response.status_code == 200
    assert get_header(response.headers, "connection") == "keep-alive"
    assert is_binary(response.body)

    unless function == nil, do: function.(response)
  end

  defp get_header(headers, key) do
    headers
    |> Enum.filter(fn({k, _}) -> k == key end)
    |> hd
    |> elem(1)
  end
end
