defmodule AshGettextFixture.PeekSealedLocker do
  @moduledoc "A change that reads a sealed locker, is refused, and carries on."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    {:error, %Ash.Error.Forbidden{}} =
      AshGettextFixture.Rules.Locker
      |> Ash.Query.for_read(:peek_sealed, %{}, actor: context.actor)
      |> Ash.read()

    changeset
  end
end

defmodule AshGettextFixture.Nested.Gate do
  @moduledoc """
  Nobody may pass it; each action first reads a sealed locker, whose refusal
  has a message of its own, and tolerates that refusal.
  """

  use Ash.Resource,
    domain: AshGettextFixture.Nested,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGettext.Resource, AshJsonApi.Resource]

  json_api do
    type("gate")
  end

  ets do
    private?(true)
  end

  actions do
    defaults([:read])

    create :pass do
      accept([])
      change({AshGettextFixture.PeekSealedLocker, []})
    end

    create :pass_the_apps_way do
      accept([])
      error_handler({AshGettextFixture.Scales, :keep, []})
      change({AshGettextFixture.PeekSealedLocker, []})
    end
  end

  policies do
    policy always() do
      forbid_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule AshGettextFixture.Nested do
  @moduledoc "A JSON:API domain whose actions read another domain's refused resource."

  use Ash.Domain,
    extensions: [AshGettext.Domain, AshJsonApi.Domain],
    validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    default_locale("en")
    text_domain("fixture")
    locale_resolver(AshGettextFixture.ActorLanguage)
  end

  json_api do
    routes do
      base_route "/gates", AshGettextFixture.Nested.Gate do
        post(:pass, route: "/plain")
        post(:pass_the_apps_way, route: "/own-handler")
      end
    end
  end

  resources do
    resource(AshGettextFixture.Nested.Gate)
  end
end

defmodule AshGettextFixture.NestedRouter do
  @moduledoc false
  use AshJsonApi.Router, domains: [AshGettextFixture.Nested]
end
