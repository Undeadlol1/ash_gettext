defmodule AshGettext.ResolverFailureTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias AshGettextFixture.ApiRouter
  alias AshGettextFixture.Flaky.Shelf

  @parsers Plug.Parsers.init(parsers: [:json], pass: ["*/*"], json_decoder: Jason)
  @minimum_sentence "Weight must be at least 30 kg"

  defp failing_actor(how), do: %{language: "ru", fail: how}

  defp messages({:error, error}) do
    error |> Ash.Error.to_error_class() |> Map.fetch!(:errors) |> Enum.map(& &1.message)
  end

  defp post_shelf(actor) do
    body = Jason.encode!(%{data: %{type: "shelf", attributes: %{weight: 40}}})

    conn =
      conn(:post, "/shelves", body)
      |> put_req_header("content-type", "application/vnd.api+json")
      |> put_req_header("accept", "application/vnd.api+json")
      |> Ash.PlugHelpers.set_actor(actor)
      |> Plug.Parsers.call(@parsers)
      |> ApiRouter.call(ApiRouter.init([]))

    {conn.status, conn.resp_body}
  end

  for how <- [:raise, :exit, :throw] do
    test "a resolver that does #{how} leaves the real error in place" do
      {result, log} =
        ExUnit.CaptureLog.with_log(fn ->
          Ash.create(Shelf, %{label: "top", weight: 5}, actor: failing_actor(unquote(how)))
        end)

      assert [@minimum_sentence] == messages(result)
      assert log =~ "AshGettextFixture.FlakyLanguage"
      assert log =~ "[warning]"
    end
  end

  test "a failing resolver leaves a read argument error in place" do
    {result, _log} =
      ExUnit.CaptureLog.with_log(fn ->
        Shelf
        |> Ash.Query.for_read(:heavier, %{than: 0}, actor: failing_actor(:raise))
        |> Ash.read()
      end)

    assert Enum.any?(messages(result), &(&1 =~ "must be greater than or equal to 1"))
  end

  test "a failing resolver does not stop json_api answering 400 with the real error" do
    {{status, body}, _log} =
      ExUnit.CaptureLog.with_log(fn -> post_shelf(failing_actor(:raise)) end)

    assert status == 400
    assert body =~ "is required"
  end

  test "an error raised inside an aborted transaction is still translated after rollback" do
    {result, _log} =
      ExUnit.CaptureLog.with_log(fn ->
        Ash.create(Shelf, %{label: "top", weight: 40},
          action: :store_twice,
          actor: failing_actor(:in_aborted_transaction)
        )
      end)

    assert ["уже занято"] == messages(result)
  end
end
