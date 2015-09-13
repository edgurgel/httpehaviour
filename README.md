# HTTPehaviour [![Build Status](https://travis-ci.org/edgurgel/httpehaviour.svg?branch=master)](https://travis-ci.org/edgurgel/httpehaviour) [![Hex pm](http://img.shields.io/hexpm/v/httpehaviour.svg?style=flat)](https://hex.pm/packages/httpehaviour)

HTTP client for Elixir, based on [HTTPoison](https://github.com/edgurgel/httpoison).

[Documentation](http://hexdocs.pm/httpehaviour/)

## But why not HTTPoison?

HTTPoison does not provide a clean way of overriding steps of the HTTP request. This project is an attempt to fix this.

## Installation

First, add HTTPehaviour to your `mix.exs` dependencies:

```elixir
def deps do
  [{:httpehaviour, "~> 0.9"}]
end
```

and run `$ mix deps.get`. Now, list the `:httpehaviour` application as part of your application dependencies:

```elixir
def application do
  [applications: [:httpehaviour]]
end
```

## Usage

```iex
iex> HTTPehaviour.start
iex> HTTPehaviour.get! "http://httparrot.herokuapp.com/get"
%HTTPehaviour.Response{
  body: "{\n  \"args\": {},\n  \"headers\": {} ...",
  headers: %{"connection" => "keep-alive", "content-length" => "517", ...},
  status_code: 200
}
iex> HTTPehaviour.get! "http://localhost:1"
** (HTTPehaviour.Error) :econnrefused
iex> HTTPehaviour.get "http://localhost:1"
{:error, %HTTPehaviour.Error{id: nil, reason: :econnrefused}}
```

You can also easily pattern match on the `HTTPehaviour.Response` struct:

```elixir
case HTTPehaviour.get(url) do
  {:ok, %HTTPehaviour.Response{status_code: 200, body: body}} ->
    IO.puts body
  {:ok, %HTTPehaviour.Response{status_code: 404}} ->
    IO.puts "Not found :("
  {:error, %HTTPehaviour.Error{reason: reason}} ->
    IO.inspect reason
end
```

### Overriding parts of the request

The request will follow like this:

* `init_request/1` which will come with the original Request;
* `process_request_url/2`, `process_request_body/2` & `process_request_headers/2`;
* The request is executed to the HTTP server;
* `process_response_status_code/2`, `process_response_headers/2`, `process_request_body/2` or `process_response_chunk/2`;
* Then finally `terminate_request/1` is called to do any cleanup and change the state;
* Response will have the state that got passed through the previous functions.

If any callback is called and returns `{ :halt, state }`, it will finish it and return `HTTPehaviour.Error`

You can define a module that implement the following callbacks

```elixir
defcallback init_request(request :: HTTPehaviour.Request.t) :: { :continue, any } | { :halt, any }

defcallback process_request_url(url :: binary, state :: any) :: { :continue, binary, any } | { :halt, any }
defcallback process_request_body(body :: binary, state :: any) :: { :continue, binary, any } | { :halt, any }
defcallback process_request_headers(headers :: HTTPehaviour.headers, state :: any) :: { :continue, HTTPehaviour.headers, any } | { :halt, any }

defcallback process_response_status_code(status_code :: integer, state :: any) :: { :continue, integer, any } | { :halt, any }
defcallback process_response_headers(headers :: HTTPehaviour.headers, state :: any) :: { :continue, HTTPehaviour.headers, any } | { :halt, any }
defcallback process_response_body(body :: binary, state :: any) :: { :continue, binary, any } | { :halt, any }
defcallback process_response_chunk(chunk :: binary, state :: any) :: { :continue, binary, any } | { :halt, any }

defcallback terminate_request(state :: any) :: any
```

Here's a simple example to build a client for the GitHub API

```elixir
defmodule GitHub do
  use HTTPehaviour.Client
  @expected_fields ~w(
    login id avatar_url gravatar_id url html_url followers_url
    following_url gists_url starred_url subscriptions_url
    organizations_url repos_url events_url received_events_url type
    site_admin name company blog location email hireable bio
    public_repos public_gists followers following created_at updated_at)

  def process_request_url(url, state) do
    { :continue, "https://api.github.com" <> url, state }
  end

  def process_response_body(body, state) do
    body = body |> Poison.decode!
                |> Dict.take(@expected_fields)
                |> Enum.map(fn({k, v}) -> {String.to_atom(k), v} end)
    { :continue, body, state }
  end

  def users do
    get!("/users/edgurgel", [], behaviour: __MODULE__).body[:public_repos]
  end
end
```

One can pass `state` data through the request and even get the final state back after the request is completed.

The request will run:

`init_request` -> `process_request_url` -> `process_request_headers` -> `process_request_body` -> `process_response_status_code` -> `process_request_headers` -> `process_response_body` -> `terminate_request`

For async requests it will do `process_response_chunk` instead of `process_response_body`

This is still a work in progress.

You can see more usage examples in the test files (located in the [`test/`](test)) directory.

## License

    Copyright © 2015 Eduardo Gurgel <eduardo@gurgel.me>

    This work is free. You can redistribute it and/or modify it under the
    terms of the MIT License. See the LICENSE file for more details.
