defmodule AshGettextFixture.ParcelStatus do
  @moduledoc false
  use Ash.Type.Enum,
    values: [
      placed: [],
      awaiting_pickup: [description: "Ready at the pickup point"],
      shipped: [label: "On its way"],
      lost: []
    ]

  use AshGettext.Enum, backend: AshGettextFixture.Gettext, text_domain: "fixture"
end
