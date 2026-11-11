defmodule AshGettextFixture.FlakyLanguage do
  @moduledoc """
  A resolver that reads a database, and so can fail: it raises, exits or
  throws when the actor says so. With `fail: :in_aborted_transaction` it
  raises only while `AshGettextFixture.AbortedTransaction` holds the
  transaction aborted, as Postgres does after a failed statement.
  """
  @behaviour AshGettext.Locale.Resolver

  @impl true
  def resolve(actor) do
    if failing?(actor),
      do: fail(actor),
      else: AshGettextFixture.ActorLanguage.resolve(Map.delete(actor, :fail))
  end

  defp failing?(%{fail: :in_aborted_transaction}),
    do: Process.get(AshGettextFixture.AbortedTransaction, false)

  defp failing?(%{fail: _how}), do: true
  defp failing?(_actor), do: false

  defp fail(%{tell: test} = actor) do
    send(test, :language_asked)
    fail(Map.delete(actor, :tell))
  end

  defp fail(%{fail: :exit}), do: exit(:no_database)
  defp fail(%{fail: :throw}), do: throw(:no_database)
  defp fail(_actor), do: raise("current transaction is aborted")
end

defmodule AshGettextFixture.AbortedTransaction do
  @moduledoc """
  Fails the action the way a unique index does in Postgres: the error is added
  inside the transaction, after which the database answers nothing until the
  transaction has ended.
  """

  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      Process.put(__MODULE__, true)

      Ash.Changeset.add_error(
        changeset,
        InvalidAttribute.exception(field: :weight, message: "has already been taken")
      )
    end)
    |> Ash.Changeset.after_transaction(fn _changeset, result ->
      Process.delete(__MODULE__)
      result
    end)
  end
end

defmodule AshGettextFixture.Flaky.Shelf do
  @moduledoc "A resource whose domain asks a resolver that can fail."

  use Ash.Resource,
    domain: AshGettextFixture.Flaky,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource, AshJsonApi.Resource]

  json_api do
    type("shelf")
  end

  ets do
    private?(true)
  end

  actions do
    defaults([:read])

    read :heavier do
      argument(:than, :integer, allow_nil?: false, constraints: [min: 1])
    end

    create :create do
      primary?(true)
      accept([:weight, :label])
      validate({AshGettextFixture.MinimumWeight, []})
    end

    create :store_twice do
      accept([:weight, :label])
      change({AshGettextFixture.AbortedTransaction, []})
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:weight, :integer, public?: true)
    attribute(:label, :string, allow_nil?: false, public?: true)
  end
end

defmodule AshGettextFixture.Flaky do
  @moduledoc "A domain whose `locale_resolver` can fail."

  use Ash.Domain,
    extensions: [AshGettext.Domain, AshJsonApi.Domain],
    validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    default_locale("en")
    text_domain("fixture")
    locale_resolver(AshGettextFixture.FlakyLanguage)
  end

  json_api do
    routes do
      base_route "/shelves", AshGettextFixture.Flaky.Shelf do
        post(:create)
      end
    end
  end

  resources do
    resource(AshGettextFixture.Flaky.Shelf)
  end
end
