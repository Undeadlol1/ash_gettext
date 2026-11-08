defmodule AshGettextFixture.ParcelStatus do
  @moduledoc false
  use AshGettext.Enum,
    backend: AshGettextFixture.Gettext,
    text_domain: "fixture",
    values: [
      placed: [label: "Order placed"],
      awaiting_pickup: [label: "Ready for pickup", description: "Ready at the pickup point"],
      shipped: [label: "On its way"],
      lost: [label: "Parcel lost"]
    ]
end
