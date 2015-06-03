defmodule HTTPehaviour.Transformer do
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init([target, behaviour, req_state]) do
    { :ok, { target, behaviour, req_state } }
  end

  def handle_info({ :hackney_response, id, { :status, status_code, _reason } },
                  { target, nil, req_state }) do
    send target, %HTTPehaviour.AsyncStatus { id: id, status_code: status_code }
    { :noreply, { target, nil, req_state } }
  end
  def handle_info({ :hackney_response, id, { :status, status_code, _reason } },
                  { target, behaviour, req_state }) do
    case behaviour.process_response_status_code(status_code, req_state) do
      { :continue, status_code, req_state } ->
        send target, %HTTPehaviour.AsyncStatus { id: id, status_code: status_code }
        { :noreply, { target, behaviour, req_state } }
      { :halt, req_state } ->
        stop_and_send_error(target, id, :halted, req_state)
    end
  end

  def handle_info({ :hackney_response, id, { :headers, headers } },
                  { target, nil, req_state }) do
    send target, %HTTPehaviour.AsyncHeaders { id: id, headers: headers }
    { :noreply, { target, nil, req_state } }
  end
  def handle_info({ :hackney_response, id, { :headers, headers } },
                  { target, behaviour, req_state }) do
      case behaviour.process_response_headers(headers, req_state) do
        { :continue, headers, req_state } ->
          send target, %HTTPehaviour.AsyncHeaders { id: id, headers: headers }
          { :noreply, { target, behaviour, req_state } }
        { :halt, req_state } ->
          stop_and_send_error(target, id, :halted, req_state)
      end
  end

  def handle_info({ :hackney_response, id, :done },
                  { target, behaviour, req_state }) do
    if behaviour do
      req_state = behaviour.terminate_request(req_state)
    end

    send target, %HTTPehaviour.AsyncEnd { id: id, state: req_state }
    { :stop, :normal, nil }
  end

  def handle_info({ :hackney_response, id, { :error, reason } },
                  { target, _, req_state }) do
    stop_and_send_error(target, id, reason, req_state)
  end

  def handle_info({ :hackney_response, id, chunk },
                  { target, nil, req_state }) do
    send target, %HTTPehaviour.AsyncChunk { id: id, chunk: chunk }
    { :noreply, { target, nil, req_state } }
  end
  def handle_info({ :hackney_response, id, chunk },
                  { target, behaviour, req_state }) do
    case behaviour.process_response_chunk(chunk, req_state) do
      { :continue, chunk, req_state } ->
        send target, %HTTPehaviour.AsyncChunk { id: id, chunk: chunk }
        { :noreply, { target, behaviour, req_state } }
      { :halt, req_state } ->
        stop_and_send_error(target, id, :halted, req_state)
    end
  end

  defp stop_and_send_error(target, id, reason, req_state) do
    send target, %HTTPehaviour.Error { id: id, reason: reason, state: req_state }
    { :stop, :normal, nil }
  end
end
