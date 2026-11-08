defmodule AshGettextBase.Domain do
  @moduledoc "A base domain, as an app writes one, so each domain does not repeat the setup."

  defmacro __using__(opts) do
    opts = Keyword.update(opts, :extensions, [AshGettext.Domain], &[AshGettext.Domain | &1])

    quote do
      use Ash.Domain, unquote(opts)

      gettext do
        backend(AshGettextFixture.Gettext)
        text_domain("fixture")
        locale_resolver(AshGettextFixture.ActorLanguage)
      end
    end
  end
end

defmodule AshGettextBase.Resource do
  @moduledoc "A base resource, as an app writes one, so each resource does not repeat the setup."

  defmacro __using__(opts) do
    opts = Keyword.update(opts, :extensions, [AshGettext.Resource], &[AshGettext.Resource | &1])

    quote do
      use Ash.Resource, unquote(opts)
    end
  end
end

defmodule AshGettextBase.Parcel do
  @moduledoc false

  use AshGettextBase.Resource,
    domain: AshGettextBase.Shipping,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshJsonApi.Resource]

  ets do
    private?(true)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:weight, :status])
      validate({AshGettextFixture.MinimumWeight, []})
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:weight, :integer, public?: true)
    attribute(:status, AshGettextFixture.ParcelStatus, public?: true)
  end
end

defmodule AshGettextBase.Shipping do
  @moduledoc false

  use AshGettextBase.Domain, validate_config_inclusion?: false

  resources do
    resource(AshGettextBase.Parcel)
  end
end

defmodule AshGettextBase.OtherCatalog do
  @moduledoc false

  use AshGettextBase.Domain, validate_config_inclusion?: false

  gettext do
    text_domain("other")
  end
end
