defmodule ScannedFixture.Gettext do
  @moduledoc false
  use Gettext.Backend, otp_app: :ash_gettext, priv: "tmp/scanned_fixture/shared"
end

defmodule ScannedFixture.QuietGettext do
  @moduledoc false
  use Gettext.Backend, otp_app: :ash_gettext, priv: "tmp/scanned_fixture/quiet"
end

defmodule ScannedFixture.NoScanGettext do
  @moduledoc false
  use Gettext.Backend, otp_app: :ash_gettext, priv: "tmp/scanned_fixture/no_scan"
end

defmodule ScannedFixture.Coins do
  @moduledoc false

  def refuse, do: Ash.Error.Invalid.exception(message: "Not enough coins")
  def left(coins), do: Ash.Error.Invalid.exception(message: "Coins left: #{coins}")
end

defmodule ScannedFixture.Parcel do
  @moduledoc false
  use Ash.Resource,
    domain: ScannedFixture.Shop,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  actions do
    defaults([:read])

    create :create do
      validate(present(:weight), message: "scanned and walked")
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:weight, :integer, public?: true)
  end
end

defmodule ScannedFixture.Crate do
  @moduledoc false
  use Ash.Resource,
    domain: ScannedFixture.Warehouse,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  actions do
    defaults([:read])
  end

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule ScannedFixture.Shop do
  @moduledoc false
  use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

  gettext do
    backend(ScannedFixture.Gettext)
    locale_resolver(AshGettextFixture.ActorLanguage)
  end

  resources do
    resource(ScannedFixture.Parcel)
  end
end

defmodule ScannedFixture.Warehouse do
  @moduledoc false
  use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

  gettext do
    backend(ScannedFixture.Gettext)
    locale_resolver(AshGettextFixture.ActorLanguage)
  end

  resources do
    resource(ScannedFixture.Crate)
  end
end

defmodule ScannedFixture.QuietParcel do
  @moduledoc false
  use Ash.Resource,
    domain: ScannedFixture.Quiet,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  actions do
    defaults([:read])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:weight, :integer, public?: true)
  end

  gettext do
    label(:weight, "Quiet weight")
  end
end

defmodule ScannedFixture.Quiet do
  @moduledoc false
  use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

  gettext do
    backend(ScannedFixture.QuietGettext)
    locale_resolver(AshGettextFixture.ActorLanguage)
    translate_errors?(false)
  end

  resources do
    resource(ScannedFixture.QuietParcel)
  end
end

defmodule ScannedFixture.NoScanParcel do
  @moduledoc false
  use Ash.Resource,
    domain: ScannedFixture.NoScan,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  actions do
    defaults([:read])

    create :create do
      validate(present(:weight), message: "walked, not scanned")
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:weight, :integer, public?: true)
  end
end

defmodule ScannedFixture.NoScan do
  @moduledoc false
  use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

  gettext do
    backend(ScannedFixture.NoScanGettext)
    locale_resolver(AshGettextFixture.ActorLanguage)
    extract_app_messages?(false)
  end

  resources do
    resource(ScannedFixture.NoScanParcel)
  end
end
