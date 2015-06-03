ExUnit.start()
{:ok, _} = :application.ensure_all_started(:httparrot)

defmodule PathHelpers do
  def fixture_path do
    Path.expand("fixtures", __DIR__)
  end

  def fixture_path(file_path) do
    Path.join fixture_path, file_path
  end
end
