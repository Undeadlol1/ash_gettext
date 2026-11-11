defmodule ScannedFixture.HeavyCheck do
  @moduledoc false
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :weight) do
      weight when is_integer(weight) and weight > 900 ->
        {:error, field: :weight, message: "too heavy: #{weight}"}

      _fine ->
        :ok
    end
  end
end
