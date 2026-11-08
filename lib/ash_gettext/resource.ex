defmodule AshGettext.Resource do
  @moduledoc """
  Opts a resource into translated action errors, enum labels and attribute names.

      defmodule MyApp.Shop.Order do
        use Ash.Resource,
          domain: MyApp.Shop,
          extensions: [AshGettext.Resource]
      end

  No attribute is rewritten and no enum is replaced; the `attributes do` block
  stays as it is. The extension points each write action's `error_handler` at
  the library, and adds one public calculation, `<attribute>_label`, for each
  attribute whose type is an `AshGettext.Enum` (see
  `AshGettext.Resource.Transformers.AddEnumLabels`). Load it to get the label
  on the record: `Ash.get!(Order, id, load: [:status_label])`.

  Every action also sets Gettext's language once, when it starts, from the
  action's actor or `context: %{locale: ...}` (see `AshGettext.SetLanguage`).

  What to translate is read from the resource's **domain** (`AshGettext.Domain`).
  A resource whose domain does not configure `gettext`, or which sets
  `translate_errors? false`, keeps its messages exactly as they are.

  To avoid writing `extensions:` on every resource, put it in the base resource
  macro the app almost certainly already has.
  """

  use Spark.Dsl.Extension,
    transformers: [
      AshGettext.Resource.Transformers.AttachErrorHandler,
      AshGettext.Resource.Transformers.AttachSetLanguage,
      AshGettext.Resource.Transformers.AddEnumLabels
    ]
end
