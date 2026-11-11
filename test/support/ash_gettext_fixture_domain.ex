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

defmodule AshGettextFixture.Scales do
  @moduledoc "What the generic `weigh` actions run, and an app's own handler for one."

  def weigh(%{arguments: %{weight: weight}}, _context) when weight < 30 do
    {:error,
     Ash.Error.Changes.InvalidArgument.exception(
       field: :weight,
       message: "weight_too_low",
       vars: [min: 30]
     )}
  end

  def weigh(%{arguments: %{weight: weight}}, _context), do: {:ok, weight}

  def keep(_input, error), do: error
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
  `AshGettext.Resource`.
  """

  use Ash.Resource,
    domain: AshGettextFixture.Shipping,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  ets do
    private?(true)
  end

  actions do
    defaults([:read, :destroy])

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

    action :weigh, :integer do
      argument(:weight, :integer, allow_nil?: false)
      run(&AshGettextFixture.Scales.weigh/2)
    end

    action :weigh_the_apps_way, :integer do
      argument(:weight, :integer, allow_nil?: false)
      error_handler({AshGettextFixture.Scales, :keep, []})
      run(&AshGettextFixture.Scales.weigh/2)
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

    attribute :status, AshGettextFixture.ParcelStatus do
      public?(true)
    end

    attribute :past_statuses, {:array, AshGettextFixture.ParcelStatus} do
      public?(true)
    end

    attribute(:secret_note, :string)
  end

  gettext do
    label(:weight, "Weight")
    label(:label, "Label")
    label(:past_statuses, "Past statuses")
  end
end

defmodule AshGettextFixture.ComparedParcel do
  @moduledoc "A resource whose only rule is a validation Ash ships, `compare`."

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
      accept([:weight])

      validate(compare(:weight, greater_than_or_equal_to: 30),
        message: "must weigh at least %{greater_than_or_equal_to} kg"
      )
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :weight, :integer do
      public?(true)
    end
  end
end

defmodule AshGettextFixture.Delivery do
  @moduledoc "A resource whose only rules are Ash's own: a required date and a typed count."

  use Ash.Resource,
    domain: AshGettextFixture.Shipping,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  ets do
    private?(true)
  end

  actions do
    defaults([:read, create: [:delivery_date, :count]])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :delivery_date, :date do
      allow_nil?(false)
      public?(true)
    end

    attribute :count, :integer do
      public?(true)
    end
  end
end

defmodule AshGettextFixture.PlainKind do
  @moduledoc false
  use Ash.Type.Enum, values: [:a, :b]
end

defmodule AshGettextFixture.Crate do
  @moduledoc "Enum attributes: one translated and already labelled, one not translated."

  use Ash.Resource,
    domain: AshGettextFixture.Shipping,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  ets do
    private?(true)
  end

  actions do
    defaults([:read, create: [:status, :kind]])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, AshGettextFixture.ParcelStatus do
      public?(true)
    end

    attribute :kind, AshGettextFixture.PlainKind do
      public?(true)
    end
  end

  calculations do
    calculate(:status_label, :string, expr("mine"), public?: true)
  end
end

defmodule AshGettextFixture.ActorLanguage do
  @moduledoc "A resolver that reads the language off the actor, and tells a test it was asked."
  @behaviour AshGettext.Locale.Resolver

  @impl true
  def resolve(%{tell: test} = actor) do
    send(test, :language_asked)
    resolve(Map.delete(actor, :tell))
  end

  def resolve(%{language: language}), do: language
  def resolve(_actor), do: nil
end

defmodule AshGettextFixture.Shipping do
  @moduledoc "A domain that translates, for the library's own suite."

  use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    default_locale("en")
    text_domain("fixture")
    locale_resolver(AshGettextFixture.ActorLanguage)
  end

  resources do
    resource(AshGettextFixture.Parcel)
    resource(AshGettextFixture.ComparedParcel)
    resource(AshGettextFixture.Crate)
    resource(AshGettextFixture.Delivery)
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
    locale_resolver(AshGettextFixture.ActorLanguage)
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
    locale_resolver(AshGettextFixture.ActorLanguage)
    translate_errors?(false)
  end

  resources do
    resource(AshGettextFixture.SwitchedOff.Parcel)
  end
end
