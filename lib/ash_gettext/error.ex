defmodule AshGettext.Error do
  @moduledoc """
  A user-visible failure with a stable `code` and a translatable `message`.

  Ash errors carry no code concept, and AshJsonApi hardcodes `code` per error
  type, so a client cannot branch on "which rule rejected this" without parsing
  a sentence. This struct pairs the two: `code` is what a client switches on,
  `message` is the sentence the person reads, written in English. It is the
  gettext msgid.

      {:error, AshGettext.Error.exception(
        code: :weight_too_low,
        field: :weight,
        message: "must weigh at least %{min} kg",
        vars: [min: 30]
      )}

  ## Fields

    * `:code` — required atom; `exception/1` raises `ArgumentError` without it.
    * `:message` — the written sentence, which is the msgid. Left as is when no
      catalog covers it.
    * `:field` — optional; when set, JSON:API points `source.pointer` at it.
    * `:vars` — interpolation values for the translated sentence; JSON:API
      also exposes them as `meta`.

  ## Translation

  `AshGettext.ErrorTranslation.translate/2` translates any struct with a binary
  `:message`, so this one needs nothing extra. The translation hook is the
  `error_handler` that `AshGettext.Resource` installs, and a preparation for
  read actions.

  ## Extraction

  `mix gettext.extract` finds `message:` given as a literal string in a
  resource or in a validation or change module it uses. A message built
  anywhere else, or passed as a module attribute or other expression, is not
  found: mark it with `dgettext_noop("ash", "...")`.

  ## JSON:API

  When `:ash_json_api` is a dependency, the error renders with its `code` as a
  string, the message as `detail`, `vars` as `meta`, and the status of its
  class. It has no `title`, so no untranslated English reaches the reader.
  """

  use Splode.Error, fields: [:code, :field, :message], class: :invalid

  @doc """
  Build the error from `opts`, which must include a `:code`.

  Raises `ArgumentError` when `:code` is missing or `nil`. The other fields
  are `:message`, `:field` and `:vars`, all optional here.

      AshGettext.Error.exception(code: :weight_too_low, message: "must weigh at least %{min} kg")
  """
  @impl true
  def exception(opts) do
    if is_nil(Keyword.get(opts, :code)) do
      raise ArgumentError, "AshGettext.Error requires a :code"
    end

    super(opts)
  end

  @doc """
  Return the error's `:message`.

  Ash and Elixir call this when they print the error, so an untranslated error
  reads as the sentence you wrote.
  """
  @impl true
  def message(%{message: message}), do: message
end

if Code.ensure_loaded?(AshJsonApi.ToJsonApiError) do
  defimpl AshJsonApi.ToJsonApiError, for: AshGettext.Error do
    def to_json_api_error(error) do
      %AshJsonApi.Error{
        id: Ash.UUID.generate(),
        status_code: AshJsonApi.Error.class_to_status(error.class),
        code: to_string(error.code),
        detail: error.message,
        source_pointer: error.field && "/data/attributes/#{error.field}",
        meta: Map.new(error.vars)
      }
    end
  end
end
