defmodule AshGettextFixture.LateReads.TooLight do
  @moduledoc "The translatable error both late read rules return."

  def error do
    Ash.Error.Query.InvalidArgument.exception(
      field: :weight,
      message: "weight_too_low",
      vars: [min: 30]
    )
  end
end

defmodule AshGettextFixture.LateReads.RefusingPreparation do
  @moduledoc "An action-level read preparation that always adds an error."

  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context),
    do: Ash.Query.add_error(query, AshGettextFixture.LateReads.TooLight.error())
end

defmodule AshGettextFixture.LateReads.RefusingValidation do
  @moduledoc "A read validation that always fails."

  use Ash.Resource.Validation

  @impl true
  def supports(_opts), do: [Ash.Query]

  @impl true
  def validate(_query, _opts, _context),
    do: {:error, AshGettextFixture.LateReads.TooLight.error()}
end

defmodule AshGettextFixture.LateReads.Shelf do
  @moduledoc "A resource whose reads fail after the library's preparation ran."

  use Ash.Resource,
    domain: AshGettextFixture.LateReads,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  ets do
    private?(true)
  end

  code_interface do
    define(:refused_by_preparation)
    define(:refused_by_validation)
  end

  actions do
    defaults([:read])

    read :refused_by_preparation do
      prepare(AshGettextFixture.LateReads.RefusingPreparation)
    end

    read :refused_by_validation do
      validate(AshGettextFixture.LateReads.RefusingValidation)
    end
  end

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule AshGettextFixture.LateReads.Cabinet do
  @moduledoc "A resource with a validation on every read, which Ash runs last."

  use Ash.Resource,
    domain: AshGettextFixture.LateReads,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  ets do
    private?(true)
  end

  code_interface do
    define(:read)
  end

  actions do
    defaults([:read])
  end

  validations do
    validate(AshGettextFixture.LateReads.RefusingValidation, on: [:read])
  end

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule AshGettextFixture.LateReads.Sower do
  @moduledoc """
  A transformer that claims to run after everything. Spark breaks the tie
  between two such transformers by its graph's vertex order, so this name is
  one that Spark sorts after the library's own transformer.
  """

  use Spark.Dsl.Transformer

  def after?(_transformer), do: true

  def transform(dsl_state) do
    with {:ok, dsl_state} <-
           Ash.Resource.Builder.add_action(dsl_state, :create, :added_create, accept: []),
         {:ok, preparation} <-
           Ash.Resource.Builder.build_preparation(AshGettextFixture.LateReads.RefusingPreparation) do
      Ash.Resource.Builder.add_action(dsl_state, :read, :added_read, preparations: [preparation])
    end
  end
end

defmodule AshGettextFixture.LateReads.ActionAdder do
  @moduledoc "Another extension whose transformer adds actions."

  use Spark.Dsl.Extension, transformers: [AshGettextFixture.LateReads.Sower]
end

defmodule AshGettextFixture.LateReads.Drawer do
  @moduledoc "A resource whose other extension adds actions after the library looked."

  use Ash.Resource,
    domain: AshGettextFixture.LateReads,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource, AshGettextFixture.LateReads.ActionAdder]

  ets do
    private?(true)
  end

  actions do
    defaults([:read])
  end

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule AshGettextFixture.LateReads do
  @moduledoc "A domain that translates, for reads whose errors come late."

  use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    default_locale("en")
    text_domain("fixture")
    locale_resolver(AshGettextFixture.ActorLanguage)
  end

  resources do
    resource(AshGettextFixture.LateReads.Shelf)
    resource(AshGettextFixture.LateReads.Cabinet)
    resource(AshGettextFixture.LateReads.Drawer)
  end
end
