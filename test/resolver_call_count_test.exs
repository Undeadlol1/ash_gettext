defmodule AshGettext.ResolverCallCountTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias AshGettextFixture.ApiRouter
  alias AshGettextFixture.Flaky.Shelf
  alias AshGettextFixture.GraphSchema
  alias AshGettextFixture.Rules.Entry
  alias AshGettextFixture.Rules.Locker

  @parsers Plug.Parsers.init(
             parsers: [:json, AshJsonApi.Plug.Parser],
             json_decoder: Jason,
             pass: ["*/*"]
           )

  defp reader, do: %{language: "ru", tell: self()}

  defp times_asked(count \\ 0) do
    receive do
      :language_asked -> times_asked(count + 1)
    after
      0 -> count
    end
  end

  defp valid(attrs) do
    Map.merge(
      %{code: "code-#{System.unique_integer([:positive])}", quantity: 1, slug: "ab", weight: 40},
      attrs
    )
  end

  defp two_mistakes, do: valid(%{code: nil, weight: 5})

  defp stored_entry(attrs \\ %{}), do: Ash.create!(Entry, valid(attrs))

  defp json_reply(method, path, attrs) do
    conn =
      conn(method, path, Jason.encode!(%{data: %{type: "entry", attributes: attrs}}))
      |> put_req_header("content-type", "application/vnd.api+json")
      |> put_req_header("accept", "application/vnd.api+json")
      |> Ash.PlugHelpers.set_actor(reader())
      |> Plug.Parsers.call(@parsers)
      |> ApiRouter.call(ApiRouter.init([]))

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp graphql_create(attrs) do
    input =
      attrs
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{inspect(value)}" end)

    {:ok, %{data: %{"createEntry" => reply}}} =
      Absinthe.run(
        "mutation { createEntry(input: {#{input}}) { errors { message shortMessage } } }",
        GraphSchema,
        context: %{actor: reader()}
      )

    reply["errors"]
  end

  describe "a failed action asks for the reader's language once" do
    test "a create with two errors" do
      assert {:error, _error} = Ash.create(Entry, two_mistakes(), actor: reader())

      assert times_asked() == 1
    end

    test "an update" do
      entry = stored_entry()

      assert {:error, _error} = Ash.update(entry, %{weight: 5}, actor: reader())

      assert times_asked() == 1
    end

    test "a destroy" do
      entry = stored_entry(%{locked: true})

      assert {:error, _error} = Ash.destroy(entry, actor: reader())

      assert times_asked() == 1
    end

    test "a policy refusal" do
      assert {:error, _error} = Ash.create(Locker, %{}, action: :open_plain, actor: reader())

      assert times_asked() == 1
    end

    test "a generic action" do
      outcome =
        Entry
        |> Ash.ActionInput.for_action(:weigh, %{weight: 5}, actor: reader())
        |> Ash.run_action()

      assert {:error, _error} = outcome
      assert times_asked() == 1
    end

    test "a read" do
      outcome =
        Entry
        |> Ash.Query.for_read(:heavier, %{than: 0}, actor: reader())
        |> Ash.read()

      assert {:error, _error} = outcome
      assert times_asked() == 1
    end
  end

  test "an error added inside the commit asks again once Ash collects it on the outer changeset" do
    outcome =
      Ash.create(Shelf, %{label: "top", weight: 40}, action: :store_twice, actor: reader())

    assert {:error, _error} = outcome
    assert times_asked() == 2
  end

  test "a bulk create asks once for each failing record" do
    result =
      Ash.bulk_create([two_mistakes(), two_mistakes()], Entry, :create,
        actor: reader(),
        return_errors?: true
      )

    assert result.error_count == 2
    assert times_asked() == 2
  end

  test "a json_api reply with two errors asks once for the action and once for the reply" do
    assert {400, %{"errors" => [_first, _second]}} =
             json_reply(:post, "/entries", two_mistakes())

    assert times_asked() == 2
  end

  test "a graphql reply with two errors asks once for the action and once for the reply" do
    assert [_first, _second] = graphql_create(two_mistakes())

    assert times_asked() == 2
  end

  describe "a working action never asks" do
    test "an update" do
      entry = stored_entry()

      Ash.update!(entry, %{weight: 50}, actor: reader())

      assert times_asked() == 0
    end

    test "a destroy" do
      entry = stored_entry()

      Ash.destroy!(entry, actor: reader())

      assert times_asked() == 0
    end

    test "a generic action" do
      Entry
      |> Ash.ActionInput.for_action(:weigh, %{weight: 50}, actor: reader())
      |> Ash.run_action!()

      assert times_asked() == 0
    end

    test "a bulk create" do
      Ash.bulk_create!([valid(%{}), valid(%{})], Entry, :create, actor: reader())

      assert times_asked() == 0
    end

    test "a json_api create" do
      assert {201, _reply} = json_reply(:post, "/entries", valid(%{}))

      assert times_asked() == 0
    end

    test "a graphql create" do
      assert [] == graphql_create(valid(%{}))

      assert times_asked() == 0
    end
  end
end
