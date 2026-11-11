defmodule ExtractorFixture.Calculation do
  @moduledoc "A calculation that fails with a message."

  use Ash.Resource.Calculation

  @impl true
  def calculate(records, _opts, _context),
    do: Enum.map(records, fn _record -> {:error, message: "the calculation refused"} end)
end
