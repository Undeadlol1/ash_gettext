defmodule AshGettext.AshMessages do
  @messages [
    {Ash.Error.Changes.Required, "is required"},
    {Ash.Error.Changes.InvalidAttribute, "is invalid"},
    {Ash.Error.Changes.InvalidArgument, "is invalid"},
    {Ash.Error.Forbidden.Policy, "You are not allowed to do this"}
  ]

  @moduledoc """
  The sentences shown for Ash's own errors, which carry no message of their own.

  Ash builds the text of these errors from code names: a missing
  `delivery_date` prints as "attribute delivery_date is required". So each one
  gets a written English sentence here. It is the msgid, and
  `mix gettext.extract` finds it for every domain with a `gettext` block.

  | Error | Sentence |
  | --- | --- |
  #{for {module, msgid} <- @messages, into: "", do: "| `#{inspect(module)}` | #{msgid} |\n"}

  An error that already has a message keeps it; that message is its msgid.
  A policy with its own message keeps that message too.
  """

  @doc "Every `{error_module, msgid}` pair."
  @spec messages() :: [{module(), String.t()}]
  def messages, do: @messages

  @doc "Every msgid, each once."
  @spec msgids() :: [String.t()]
  def msgids, do: @messages |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

  @doc """
  The msgid for `error`, or `nil` when it already has a message or is not listed.
  """
  @spec msgid(term()) :: String.t() | nil
  def msgid(%{message: message}) when is_binary(message), do: nil

  def msgid(%Ash.Error.Forbidden.Policy{custom_message: custom}) when is_binary(custom),
    do: custom

  def msgid(%module{}) do
    Enum.find_value(@messages, fn {listed, msgid} -> listed == module && msgid end)
  end

  def msgid(_other), do: nil
end

defmodule AshGettext.AshMessages.Translated do
  @moduledoc """
  An Ash error whose text is now the translated sentence.

  Ash prints its own errors from their module, not from a field, so the
  translated text needs a struct that prints it. This one keeps the
  `original` error, its `field`, `path` and `class`, and its `message` is
  the sentence the person reads. `Exception.message/1` returns it, and
  JSON:API renders the original error with that sentence as its `detail`.
  """

  use Splode.Error, fields: [:original, :field, :message], class: :invalid

  @impl true
  def message(%{message: message}), do: message
end

if Code.ensure_loaded?(AshJsonApi.ToJsonApiError) do
  defimpl AshJsonApi.ToJsonApiError, for: AshGettext.AshMessages.Translated do
    def to_json_api_error(%{original: original, message: message}) do
      original
      |> AshJsonApi.ToJsonApiError.to_json_api_error()
      |> List.wrap()
      |> Enum.map(&%{&1 | detail: message})
    end
  end
end
