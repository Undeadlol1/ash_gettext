defmodule AshGettextFixture.ApiNote do
  @moduledoc "A note served over JSON:API; the domain it belongs to is passed in."

  defmacro __using__(opts) do
    domain = Keyword.fetch!(opts, :domain)
    type = Keyword.fetch!(opts, :type)

    quote do
      use Ash.Resource,
        domain: unquote(domain),
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshGettext.Resource, AshJsonApi.Resource]

      json_api do
        type(unquote(type))
      end

      ets do
        private?(true)
      end

      actions do
        defaults([:read])

        create :create do
          primary?(true)
          accept([:title, :weight])
          validate({AshGettextFixture.MinimumWeight, []})
        end
      end

      attributes do
        uuid_primary_key(:id)
        attribute(:title, :string, allow_nil?: false, public?: true)
        attribute(:weight, :integer, public?: true)
      end
    end
  end
end

defmodule AshGettextFixture.Api.Note do
  @moduledoc false
  use AshGettextFixture.ApiNote, domain: AshGettextFixture.Api, type: "note"
end

defmodule AshGettextFixture.Api.Vault do
  @moduledoc "A resource nobody may create, to reach a failed policy over HTTP."

  use Ash.Resource,
    domain: AshGettextFixture.Api,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGettext.Resource, AshJsonApi.Resource]

  json_api do
    type("vault")
  end

  ets do
    private?(true)
  end

  actions do
    defaults([:read, create: []])
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

defmodule AshGettextFixture.Api do
  @moduledoc "A JSON:API domain that translates its replies."

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
    error_handler({AshGettext.JsonApi, :translate_error, []})

    routes do
      base_route "/notes", AshGettextFixture.Api.Note do
        get(:read)
        post(:create)
      end

      base_route "/vaults", AshGettextFixture.Api.Vault do
        post(:create)
      end
    end
  end

  resources do
    resource(AshGettextFixture.Api.Note)
    resource(AshGettextFixture.Api.Vault)
  end
end

defmodule AshGettextFixture.OwnHandler do
  @moduledoc "An app's own JSON:API error handler that adds to `meta`, then translates."

  def handle_error(error, context) do
    %{error | meta: Map.put(error.meta || %{}, :support_code, "S-1")}
    |> AshGettext.JsonApi.translate_error(context)
  end
end

defmodule AshGettextFixture.OwnHandlerApi.Note do
  @moduledoc false
  use AshGettextFixture.ApiNote, domain: AshGettextFixture.OwnHandlerApi, type: "own_note"
end

defmodule AshGettextFixture.OwnHandlerApi do
  @moduledoc "A JSON:API domain whose app wrote its own error handler."

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
    error_handler({AshGettextFixture.OwnHandler, :handle_error, []})

    routes do
      base_route "/own_notes", AshGettextFixture.OwnHandlerApi.Note do
        get(:read)
        post(:create)
      end
    end
  end

  resources do
    resource(AshGettextFixture.OwnHandlerApi.Note)
  end
end

defmodule AshGettextFixture.StockApi.Note do
  @moduledoc false
  use AshGettextFixture.ApiNote, domain: AshGettextFixture.StockApi, type: "stock_note"
end

defmodule AshGettextFixture.StockApi do
  @moduledoc "A JSON:API domain that never added the error handler."

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
      base_route "/stock_notes", AshGettextFixture.StockApi.Note do
        get(:read)
        post(:create)
      end
    end
  end

  resources do
    resource(AshGettextFixture.StockApi.Note)
  end
end

defmodule AshGettextFixture.ApiRouter do
  @moduledoc false
  use AshJsonApi.Router,
    domains: [
      AshGettextFixture.Api,
      AshGettextFixture.OwnHandlerApi,
      AshGettextFixture.StockApi
    ]
end
