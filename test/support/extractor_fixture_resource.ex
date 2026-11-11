defmodule ExtractorFixture.Parcel do
  @moduledoc "A resource whose messages live only in modules its actions point at."

  use Ash.Resource,
    domain: ExtractorFixture.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  actions do
    defaults([:read])

    create :create do
      manual(ExtractorFixture.Manual)
    end

    action :ship, :string do
      run(ExtractorFixture.Run)
    end
  end

  attributes do
    uuid_primary_key(:id)
  end

  calculations do
    calculate(:label, :string, ExtractorFixture.Calculation)
  end
end

defmodule ExtractorFixture.Domain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(ExtractorFixture.Parcel)
  end
end
