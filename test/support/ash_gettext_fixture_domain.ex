defmodule AshGettextFixture.MinimumWeight do
  @moduledoc """
  A validation whose error message is a msgid rather than a sentence.

  This is the shape the library expects of a translatable error: the message
  identifies the string, and `vars` carries whatever the sentence interpolates.
  """

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @minimum 30

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :weight) do
      weight when is_integer(weight) and weight < @minimum ->
        {:error,
         InvalidAttribute.exception(
           field: :weight,
           message: "weight_too_low",
           vars: [min: @minimum]
         )}

      _acceptable ->
        :ok
    end
  end
end

defmodule AshGettextFixture.UntranslatedRule do
  @moduledoc """
  A validation whose message is a plain sentence no catalog covers.

  Proves adoption is non-destructive: a message the catalogs do not know must
  come out the far side byte-for-byte unchanged.
  """

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :label) do
      "reject me" ->
        {:error, InvalidAttribute.exception(field: :label, message: "this label is not allowed")}

      _acceptable ->
        :ok
    end
  end
end

defmodule AshGettextFixture.WeighedParcel do
  @moduledoc """
  The resource the error-layer fixtures all need: weighed, ETS-backed, opted in.

  The fixtures that use this differ only in which domain they belong to and
  whether they bring their own error handler, so the resource itself is written
  once here and the differences are passed in.
  """

  defmacro __using__(opts) do
    domain = Keyword.fetch!(opts, :domain)
    error_handler = Keyword.get(opts, :error_handler)

    quote do
      use Ash.Resource,
        domain: unquote(domain),
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshGettext.Resource]

      ets do
        private?(true)
      end

      actions do
        defaults([:read])

        create :create do
          primary?(true)
          accept([:weight])

          if unquote(error_handler) do
            error_handler(unquote(error_handler))
          end

          validate({AshGettextFixture.MinimumWeight, []})
        end
      end

      attributes do
        uuid_primary_key(:id)

        attribute :weight, :integer do
          public?(true)
        end
      end
    end
  end
end

defmodule AshGettextFixture.Parcel do
  @moduledoc """
  A resource that opts into translated errors and nothing else.

  Note what is *absent*: no attribute here is declared differently because of
  `AshGettext.Resource`, which is the notebook's §2.1a promise made concrete.
  """

  use Ash.Resource,
    domain: AshGettextFixture.Shipping,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  ets do
    private?(true)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:weight, :label])
      validate({AshGettextFixture.MinimumWeight, []})
      validate({AshGettextFixture.UntranslatedRule, []})
    end

    update :relabel do
      primary?(true)
      accept([:label])
      require_atomic?(false)
      validate({AshGettextFixture.UntranslatedRule, []})
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :weight, :integer do
      public?(true)
    end

    attribute :label, :string do
      public?(true)
    end
  end
end

defmodule AshGettextFixture.Shipping do
  @moduledoc "A domain that translates, for the library's own suite."

  use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    default_locale("en")
    text_domain("fixture")
    locale_resolvers([AshGettext.Locale.Context])
  end

  resources do
    resource(AshGettextFixture.Parcel)
  end
end

defmodule AshGettextFixture.Untranslated.Parcel do
  @moduledoc "A resource whose domain does not configure gettext at all."

  use AshGettextFixture.WeighedParcel, domain: AshGettextFixture.Untranslated
end

defmodule AshGettextFixture.Untranslated do
  @moduledoc "A domain with no `gettext` block, to prove the opt-in is real."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshGettextFixture.Untranslated.Parcel)
  end
end

defmodule AshGettextFixture.CustomHandler do
  @moduledoc "An app-supplied error handler, to prove the transformer defers to it."

  def handle(_changeset, error), do: %{error | message: "handled by the app"}
end

defmodule AshGettextFixture.Opinionated.Parcel do
  @moduledoc "A resource whose create action already declares its own error handler."

  use AshGettextFixture.WeighedParcel,
    domain: AshGettextFixture.Opinionated,
    error_handler: {AshGettextFixture.CustomHandler, :handle, []}
end

defmodule AshGettextFixture.Opinionated do
  @moduledoc "A translating domain whose resource keeps its own error handler."

  use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    text_domain("fixture")
  end

  resources do
    resource(AshGettextFixture.Opinionated.Parcel)
  end
end

defmodule AshGettextFixture.SwitchedOff.Parcel do
  @moduledoc "A resource in a domain that has switched translation off."

  use AshGettextFixture.WeighedParcel, domain: AshGettextFixture.SwitchedOff
end

defmodule AshGettextFixture.SwitchedOff do
  @moduledoc "A domain that configures gettext but turns error translation off."

  use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    text_domain("fixture")
    translate_errors?(false)
  end

  resources do
    resource(AshGettextFixture.SwitchedOff.Parcel)
  end
end
