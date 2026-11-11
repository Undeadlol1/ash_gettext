defmodule AshGettext.NestedRefusalTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias AshGettextFixture.NestedRouter

  @parsers Plug.Parsers.init(
             parsers: [:json, AshJsonApi.Plug.Parser],
             json_decoder: Jason,
             pass: ["*/*"]
           )
  @forbidden_on_the_wire "Вам нельзя это делать"

  defp details(path) do
    conn =
      conn(:post, path, Jason.encode!(%{data: %{type: "gate", attributes: %{}}}))
      |> put_req_header("content-type", "application/vnd.api+json")
      |> put_req_header("accept", "application/vnd.api+json")
      |> Ash.PlugHelpers.set_actor(%{language: "ru"})
      |> Plug.Parsers.call(@parsers)
      |> NestedRouter.call(NestedRouter.init([]))

    {conn.status,
     conn.resp_body |> Jason.decode!() |> Map.fetch!("errors") |> Enum.map(& &1["detail"])}
  end

  test "a tolerated inner refusal does not lend its message to the action's own refusal" do
    assert {403, [@forbidden_on_the_wire]} == details("/gates/plain")
  end

  test "nor when the action keeps the app's own error handler" do
    assert {403, [@forbidden_on_the_wire]} == details("/gates/own-handler")
  end
end
