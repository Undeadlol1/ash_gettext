defmodule AshGettextFixture.BadTitle do
  @moduledoc "A validation that rejects a title with an error that has no message."

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :title) do
      "bad" -> {:error, Ash.Error.Changes.InvalidAttribute.exception(field: :title)}
      _acceptable -> :ok
    end
  end
end

defmodule AshGettextFixture.GraphqlNote do
  @moduledoc "A note served over GraphQL; the domain it belongs to is passed in."

  defmacro __using__(opts) do
    domain = Keyword.fetch!(opts, :domain)
    type = Keyword.fetch!(opts, :type)

    quote do
      use Ash.Resource,
        domain: unquote(domain),
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshGettext.Resource, AshGraphql.Resource]

      graphql do
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
          allow_nil_input([:title])
          validate({AshGettextFixture.MinimumWeight, []})
          validate({AshGettextFixture.BadTitle, []})
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

defmodule AshGettextFixture.Graph.Note do
  @moduledoc false
  use AshGettextFixture.GraphqlNote, domain: AshGettextFixture.Graph, type: :note
end

defmodule AshGettextFixture.Graph.Vault do
  @moduledoc "A resource nobody may create, to reach a failed policy."

  use Ash.Resource,
    domain: AshGettextFixture.Graph,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGettext.Resource, AshGraphql.Resource]

  graphql do
    type(:vault)
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

defmodule AshGettextFixture.Graph do
  @moduledoc "A GraphQL domain with a `gettext` block and nothing else set up."

  use Ash.Domain,
    extensions: [AshGettext.Domain, AshGraphql.Domain],
    validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    default_locale("en")
    text_domain("fixture")
    locale_resolver(AshGettextFixture.ActorLanguage)
  end

  graphql do
    queries do
      get(AshGettextFixture.Graph.Note, :note, :read, allow_nil?: false)
    end

    mutations do
      create(AshGettextFixture.Graph.Note, :create_note, :create)
      create(AshGettextFixture.Graph.Vault, :create_vault, :create)
    end
  end

  resources do
    resource(AshGettextFixture.Graph.Note)
    resource(AshGettextFixture.Graph.Vault)
  end
end

defmodule AshGettextFixture.GraphOwnHandler do
  @moduledoc "An app's own GraphQL error handler, which adds to the error."

  def handle_error(error, _context, support_code) do
    Map.put(error, :support_code, support_code)
  end
end

defmodule AshGettextFixture.OwnGraph.Note do
  @moduledoc false
  use AshGettextFixture.GraphqlNote, domain: AshGettextFixture.OwnGraph, type: :own_note
end

defmodule AshGettextFixture.OwnGraph do
  @moduledoc "A GraphQL domain whose app wrote its own error handler."

  use Ash.Domain,
    extensions: [AshGettext.Domain, AshGraphql.Domain],
    validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    default_locale("en")
    text_domain("fixture")
    locale_resolver(AshGettextFixture.ActorLanguage)
  end

  graphql do
    error_handler({AshGettextFixture.GraphOwnHandler, :handle_error, ["S-1"]})

    mutations do
      create(AshGettextFixture.OwnGraph.Note, :create_own_note, :create)
    end
  end

  resources do
    resource(AshGettextFixture.OwnGraph.Note)
  end
end

defmodule AshGettextFixture.StockGraph.Note do
  @moduledoc false
  use AshGettextFixture.GraphqlNote, domain: AshGettextFixture.StockGraph, type: :stock_note
end

defmodule AshGettextFixture.StockGraph do
  @moduledoc "A GraphQL domain that switched error translation off."

  use Ash.Domain,
    extensions: [AshGettext.Domain, AshGraphql.Domain],
    validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    default_locale("en")
    text_domain("fixture")
    locale_resolver(AshGettextFixture.ActorLanguage)
    translate_errors?(false)
  end

  graphql do
    mutations do
      create(AshGettextFixture.StockGraph.Note, :create_stock_note, :create)
    end
  end

  resources do
    resource(AshGettextFixture.StockGraph.Note)
  end
end

defmodule AshGettextFixture.GraphSchema do
  @moduledoc false
  use Absinthe.Schema

  use AshGraphql,
    domains: [
      AshGettextFixture.Graph,
      AshGettextFixture.Rules,
      AshGettextFixture.OwnGraph,
      AshGettextFixture.StockGraph
    ]

  query do
  end

  mutation do
  end
end
