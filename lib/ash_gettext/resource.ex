defmodule AshGettext.Resource do
  @moduledoc """
  Opts a resource into translated action errors.

      defmodule MyApp.Shop.Order do
        use Ash.Resource,
          domain: MyApp.Shop,
          extensions: [AshGettext.Resource]
      end

  Adding this changes nothing about the resource's shape. No attribute is
  rewritten, no enum is replaced, no field is injected into any payload — the
  extension only points each write action's `error_handler` at the library.
  Adopting `ash_gettext` never requires a change to a resource's
  `attributes do` block.

  What to translate is read from the resource's **domain** (`AshGettext.Domain`).
  A resource whose domain does not configure `gettext`, or which sets
  `translate_errors? false`, keeps its messages exactly as they are.

  To avoid writing `extensions:` on every resource, put it in the base resource
  macro the app almost certainly already has.
  """

  use Spark.Dsl.Extension,
    transformers: [AshGettext.Resource.Transformers.InstallErrorHandler]
end
