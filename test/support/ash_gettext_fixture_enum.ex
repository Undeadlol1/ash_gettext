defmodule AshGettextFixture.ParcelStatus do
  @moduledoc false
  use Ash.Type.Enum,
    values: [
      placed: [],
      awaiting_pickup: [],
      shipped: [label: "On its way"],
      lost: []
    ]
end
