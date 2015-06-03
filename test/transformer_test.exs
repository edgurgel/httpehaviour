defmodule TransformerTest do
  use ExUnit.Case
  import HTTPehaviour.Transformer

  defmodule ContinueClient do
    use HTTPehaviour.Client

    def init_request(_args), do: { :continue, [:init_request] }

    def process_response_status_code(status_code, state), do: { :continue, status_code, [:process_response_status_code | state] }
    def process_response_headers(headers, state), do: { :continue, headers, [:process_response_headers | state] }
    def process_response_chunk(chunk, state), do: { :continue, chunk, [:process_response_chunk | state] }

    def terminate_request(state), do: [:terminate_request | state]
  end

  defmodule HaltClient do
    use HTTPehaviour.Client

    def init_request(_args), do: { :halt, [:init_request] }

    def process_response_status_code(_status_code, state), do: { :halt, [:process_response_status_code | state] }
    def process_response_headers(_headers, state), do: { :halt, [:process_response_headers | state] }
    def process_response_chunk(_chunk, state), do: { :halt, [:process_response_chunk | state] }

    def terminate_request(state), do: [:terminate_request | state]
  end

  test "receive response headers" do
    headers = [{"header", "value"}]
    message = { :headers, headers }
    state   = { self, nil, :req_state }
    assert handle_info({ :hackney_response, :id, message }, state) == { :noreply, state }

    assert_receive %HTTPehaviour.AsyncHeaders{ id: :id, headers: ^headers }
  end

  test "receive response headers having a behaviour with continue" do
    headers = [{"header", "value"}]
    message = { :headers, headers }
    state   = { self, ContinueClient, [:req_state] }
    new_state = { self, ContinueClient, [:process_response_headers, :req_state] }
    assert handle_info({ :hackney_response, :id, message }, state) == { :noreply, new_state }

    assert_receive %HTTPehaviour.AsyncHeaders{ id: :id, headers: ^headers }
  end

  test "receive response headers having a behaviour with halt" do
    headers = [{"header", "value"}]
    message = { :headers, headers }
    state   = { self, HaltClient, [:req_state] }
    new_state = [:process_response_headers, :req_state]
    assert handle_info({ :hackney_response, :id, message }, state) == { :stop, :normal, nil }

    assert_receive %HTTPehaviour.Error{ id: :id, reason: :halted, state: ^new_state }
  end

  test "receive status code" do
    message = { :status, 200, :reason }
    state   = { self, nil, :req_state }
    assert handle_info({ :hackney_response, :id, message }, state) == { :noreply, state }

    assert_receive %HTTPehaviour.AsyncStatus{ id: :id, status_code: 200 }
  end

  test "receive status code having a behaviour with continue" do
    message = { :status, 200, :reason }
    state   = { self, ContinueClient, [:req_state] }
    new_state   = { self, ContinueClient, [:process_response_status_code, :req_state] }
    assert handle_info({ :hackney_response, :id, message }, state) == { :noreply, new_state }

    assert_receive %HTTPehaviour.AsyncStatus{ id: :id, status_code: 200 }
  end

  test "receive status code having a behaviour with halt" do
    message = { :status, 200, :reason }
    state   = { self, HaltClient, [:req_state] }
    new_state   = [:process_response_status_code, :req_state]
    assert handle_info({ :hackney_response, :id, message }, state) == { :stop, :normal, nil }

    assert_receive %HTTPehaviour.Error{ id: :id, reason: :halted, state: ^new_state }
  end

  test "receive body chunk" do
    message = "chunk"
    state   = { self, nil, :req_state }
    assert handle_info({ :hackney_response, :id, message }, state) == { :noreply, state }

    assert_receive %HTTPehaviour.AsyncChunk{ id: :id, chunk: ^message }
  end

  test "receive body chunk having a behaviour with continue" do
    message = "chunk"
    state   = { self, ContinueClient, [:req_state] }
    new_state   = { self, ContinueClient, [:process_response_chunk, :req_state] }
    assert handle_info({ :hackney_response, :id, message }, state) == { :noreply, new_state }

    assert_receive %HTTPehaviour.AsyncChunk{ id: :id, chunk: ^message }
  end

  test "receive body chunk having a behaviour with halt" do
    message = "chunk"
    state   = { self, HaltClient, [:req_state] }
    new_state   = [:process_response_chunk, :req_state]
    assert handle_info({ :hackney_response, :id, message }, state) == { :stop, :normal, nil }

    assert_receive %HTTPehaviour.Error{ id: :id, reason: :halted, state: ^new_state }
  end

  test "receive done" do
    message = :done
    state   = { self, nil, :req_state }
    assert handle_info({ :hackney_response, :id, message }, state) == { :stop, :normal, nil }

    assert_receive %HTTPehaviour.AsyncEnd{ id: :id ,state: :req_state }
  end

  test "receive done having a behaviour" do
    message = :done
    state   = { self, ContinueClient, [:req_state] }
    assert handle_info({ :hackney_response, :id, message }, state) == { :stop, :normal, nil }

    assert_receive %HTTPehaviour.AsyncEnd{ id: :id, state: [:terminate_request, :req_state]}
  end
end
