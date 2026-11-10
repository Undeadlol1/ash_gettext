defmodule AshGettext.AshMessages do
  @messages [
    {Ash.Error.Changes.InvalidAttribute, "is invalid"},
    {Ash.Error.Changes.InvalidArgument, "is invalid"},
    {Ash.Error.Forbidden.Policy, "You are not allowed to do this"}
  ]

  @moduledoc """
  The sentences shown for Ash's own errors when they carry no message.

  Ash builds the text of these errors from code names, so each one gets a
  written English sentence here. It is the msgid, and `mix gettext.extract`
  finds it for every domain with a `gettext` block. The translated sentence
  goes into the error's own text field (`message`, or `custom_message` for a
  policy), so the error stays Ash's own struct.

  `Ash.Error.Changes.Required` is not listed: it has no text field, and
  replacing it with another struct would break code that matches on it.

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
