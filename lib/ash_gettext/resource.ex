defmodule AshGettext.Resource do
  @moduledoc """
  Opts a resource into translated action errors, enum labels and attribute names.

      defmodule MyApp.Shop.Order do
        use Ash.Resource,
          domain: MyApp.Shop,
          extensions: [AshGettext.Resource]
      end

  No attribute is rewritten and no enum is replaced; the `attributes do` block
  stays as it is. The extension points each action's `error_handler` at
  the library (a preparation does the same for reads), and adds one public
  calculation, `<attribute>_label`, for each
  attribute whose type is an `AshGettext.Enum` (see
  `AshGettext.Resource.Transformers.AddEnumLabels`). Load it to get the label
  on the record: `Ash.get!(Order, id, load: [:status_label])`.

  Attribute names are written by you, never made from the code name:

      gettext do
        label :delivery_date, "Delivery date"
      end

  `AshGettext.attribute_label/2` translates that text. An attribute with no
  `label` raises. A `label` for an attribute the resource lacks fails to compile.

  Labels loaded on records and errors from actions use the language of the
  action's actor, else Gettext's current language. No action changes the
  process language.

  What to translate is read from the resource's **domain** (`AshGettext.Domain`).
  A resource whose domain does not configure `gettext`, or which sets
  `translate_errors? false`, keeps its messages exactly as they are.

  To avoid writing `extensions:` on every resource, put it in the base resource
  macro the app almost certainly already has.
  """

  @label %Spark.Dsl.Entity{
    name: :label,
    describe: "The text a person reads for an attribute. Written by you, then translated.",
    examples: [~S|label :delivery_date, "Delivery date"|],
    target: AshGettext.Resource.Label,
    args: [:attribute, :text],
    schema: [
      attribute: [type: :atom, required: true, doc: "The attribute the text names."],
      text: [type: :string, required: true, doc: "The text, in the source language."]
    ]
  }

  @gettext %Spark.Dsl.Section{
    name: :gettext,
    describe: "The texts a person reads for this resource's attributes.",
    examples: [
      """
      gettext do
        label :delivery_date, "Delivery date"
      end
      """
    ],
    entities: [@label]
  }

  use Spark.Dsl.Extension,
    sections: [@gettext],
    verifiers: [AshGettext.Resource.Verifiers.ValidateLabels],
    transformers: [AshGettext.Resource.Transformers.AddEnumLabels],
    persisters: [AshGettext.Resource.Transformers.AttachErrorHandler]
end
