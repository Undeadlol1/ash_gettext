defmodule AshGettextFixture.UnknownError do
  @moduledoc "A Splode error no transport and no catalog has ever heard of."

  use Splode.Error, fields: [:reason], class: :invalid

  def message(%{reason: reason}), do: "unknown error: #{reason}"
end

defmodule AshGettextFixture.UnlistedSentence do
  @moduledoc "A validation whose sentence has variables and no catalog entry."

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :note) do
      "unlisted" ->
        {:error,
         InvalidAttribute.exception(
           field: :note,
           message: "needs %{missing} more words",
           vars: [missing: 2]
         )}

      _acceptable ->
        :ok
    end
  end
end

defmodule AshGettextFixture.UnknownRule do
  @moduledoc "A validation that fails with `AshGettextFixture.UnknownError`."

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :note) do
      "unknown" -> {:error, AshGettextFixture.UnknownError.exception(reason: "odd")}
      _acceptable -> :ok
    end
  end
end

defmodule AshGettextFixture.Rules.Entry do
  @moduledoc """
  One resource with a rule of every kind Ash ships, served over JSON:API and
  GraphQL, for the error kinds beyond "is required".
  """

  use Ash.Resource,
    domain: AshGettextFixture.Rules,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource, AshJsonApi.Resource, AshGraphql.Resource]

  json_api do
    type("entry")
  end

  graphql do
    type(:entry)
  end

  ets do
    private?(true)
  end

  actions do
    defaults([:read])

    read :heavier do
      argument(:than, :integer, allow_nil?: false, constraints: [min: 1])
      filter(expr(weight > ^arg(:than)))
    end

    read :by_code do
      get?(true)
      argument(:code, :string, allow_nil?: false)
      filter(expr(code == ^arg(:code)))
    end

    create :create do
      primary?(true)
      accept([:code, :quantity, :slug, :handle, :nickname, :stock, :weight, :note, :locked])
      argument(:size, :integer, constraints: [min: 1])
      validate({AshGettextFixture.MinimumWeight, []})
      validate({AshGettextFixture.UnlistedSentence, []})
      validate({AshGettextFixture.UnknownRule, []})
    end

    update :update do
      primary?(true)
      require_atomic?(false)
      accept([:code, :quantity, :slug, :handle, :nickname, :stock, :weight, :note])
      validate({AshGettextFixture.MinimumWeight, []})
    end

    destroy :destroy do
      primary?(true)
      require_atomic?(false)
      validate(attribute_equals(:locked, false))
    end

    action :weigh, :integer do
      argument(:weight, :integer, allow_nil?: false)
      run(&AshGettextFixture.Scales.weigh/2)
    end
  end

  validations do
    validate(present(:code))
    validate(compare(:quantity, greater_than: 0))
    validate(match(:slug, ~r/^[a-z]+$/))
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:code, :string, public?: true)
    attribute(:quantity, :integer, public?: true)
    attribute(:slug, :string, public?: true)
    attribute(:handle, :string, public?: true, constraints: [match: ~r/^[a-z]+$/])
    attribute(:nickname, :string, public?: true, constraints: [max_length: 5])
    attribute(:stock, :integer, public?: true, constraints: [min: 1])
    attribute(:weight, :integer, public?: true)
    attribute(:note, :string, public?: true)
    attribute(:locked, :boolean, public?: true, default: false)
  end

  identities do
    identity(:unique_code, [:code], pre_check_with: AshGettextFixture.Rules)
  end
end

defmodule AshGettextFixture.Rules.Locker do
  @moduledoc "Nobody may open it: one policy without a message, one with."

  use Ash.Resource,
    domain: AshGettextFixture.Rules,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGettext.Resource, AshJsonApi.Resource, AshGraphql.Resource]

  json_api do
    type("locker")
  end

  graphql do
    type(:locker)
  end

  ets do
    private?(true)
  end

  actions do
    defaults([:read])
    read(:peek_plain)
    read(:peek_sealed)
    create(:open_plain, accept: [])
    create(:open_sealed, accept: [])
  end

  policies do
    policy action(:open_plain) do
      forbid_if(always())
    end

    policy action(:open_sealed) do
      error_message("order_already_placed")
      forbid_if(always())
    end

    policy action(:peek_plain) do
      access_type(:strict)
      forbid_if(always())
    end

    policy action(:peek_sealed) do
      access_type(:strict)
      error_message("order_already_placed")
      forbid_if(always())
    end

    policy action(:read) do
      authorize_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule AshGettextFixture.Rules do
  @moduledoc "A domain served over JSON:API and GraphQL that translates, with nothing else set up."

  use Ash.Domain,
    extensions: [AshGettext.Domain, AshJsonApi.Domain, AshGraphql.Domain],
    validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    default_locale("en")
    text_domain("fixture")
    locale_resolver(AshGettextFixture.ActorLanguage)
  end

  json_api do
    routes do
      base_route "/entries", AshGettextFixture.Rules.Entry do
        get(:read)
        post(:create)
        patch(:update)
        delete(:destroy)
        route(:post, "/weigh", :weigh)
      end

      base_route "/lockers", AshGettextFixture.Rules.Locker do
        post(:open_plain, route: "/plain")
        post(:open_sealed, route: "/sealed")
      end
    end
  end

  graphql do
    queries do
      get(AshGettextFixture.Rules.Entry, :entry, :read, allow_nil?: false)
    end

    mutations do
      create(AshGettextFixture.Rules.Entry, :create_entry, :create)
      update(AshGettextFixture.Rules.Entry, :update_entry, :update)
      destroy(AshGettextFixture.Rules.Entry, :destroy_entry, :destroy)
      action(AshGettextFixture.Rules.Entry, :weigh_entry, :weigh)
      create(AshGettextFixture.Rules.Locker, :open_plain_locker, :open_plain)
      create(AshGettextFixture.Rules.Locker, :open_sealed_locker, :open_sealed)
    end
  end

  resources do
    resource(AshGettextFixture.Rules.Entry)
    resource(AshGettextFixture.Rules.Locker)
  end
end
