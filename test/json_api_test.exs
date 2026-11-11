defmodule AshGettext.JsonApiTest do
  @moduledoc """
  AshJsonApi writes the text of some errors itself ("is required", "No note
  record found with ..."), after every Ash error handler has run. These send
  real HTTP requests and read the reply the client gets.
  """

  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias AshGettextFixture.Api
  alias AshGettextFixture.ApiRouter
  alias AshGettextFixture.Gettext, as: Backend

  @russian %{language: "ru"}
  @english %{language: "en"}
  @parsers Plug.Parsers.init(
             parsers: [:json, AshJsonApi.Plug.Parser],
             json_decoder: Jason,
             pass: ["*/*"]
           )

  defp reply(method, path, attributes, actor, domain \\ Api),
    do:
      request(
        method,
        path,
        attributes,
        actor,
        &AshGettext.Plug.call(&1, AshGettext.Plug.init(domain: domain))
      )

  defp reply_without_the_plug(method, path, attributes, actor),
    do: request(method, path, attributes, actor, & &1)

  defp request(method, path, attributes, actor, set_language) do
    body = attributes && Jason.encode!(%{data: %{type: type_of(path), attributes: attributes}})

    conn =
      conn(method, path, body)
      |> put_req_header("content-type", "application/vnd.api+json")
      |> put_req_header("accept", "application/vnd.api+json")
      |> Ash.PlugHelpers.set_actor(actor)
      |> set_language.()
      |> Plug.Parsers.call(@parsers)
      |> ApiRouter.call(ApiRouter.init([]))

    [error] = Jason.decode!(conn.resp_body)["errors"]
    Map.put(error, "status", conn.status)
  end

  defp type_of("/notes"), do: "note"
  defp type_of("/own_notes"), do: "own_note"
  defp type_of("/stock_notes"), do: "stock_note"
  defp type_of("/vaults"), do: "vault"

  defp missing_note, do: "/notes/#{Ash.UUID.generate()}"
  defp without_id(error), do: Map.delete(error, "id")

  describe "a Russian reader" do
    test "reads a missing required value as the Russian sentence" do
      assert %{"code" => "required", "detail" => "обязательное поле", "status" => 400} =
               reply(:post, "/notes", %{}, @russian)
    end

    test "still gets the field the error is about" do
      assert %{"source" => %{"pointer" => "/data/attributes/title"}} =
               reply(:post, "/notes", %{}, @russian)
    end

    test "reads a record that is not there as the Russian sentence" do
      assert %{"code" => "not_found", "detail" => "не найдено", "status" => 404} =
               reply(:get, missing_note(), nil, @russian)
    end

    test "reads a failed policy as the Russian sentence" do
      assert %{"code" => "forbidden", "detail" => "Вам нельзя это делать", "status" => 403} =
               reply(:post, "/vaults", %{}, @russian)
    end

    test "reads a validation message with its values, and keeps them in meta" do
      assert %{"detail" => "Вес должен быть не менее 30 кг", "meta" => %{"min" => 30}} =
               reply(:post, "/notes", %{title: "t", weight: 5}, @russian)
    end

    test "gets a text nobody translated exactly as AshJsonApi wrote it" do
      assert %{"detail" => "no route found"} = reply(:get, "/nowhere", nil, @russian)
    end
  end

  describe "a reader in the source language" do
    test "gets the same reply as a domain with translation switched off" do
      assert without_id(reply(:post, "/notes", %{}, @english)) ==
               without_id(reply(:post, "/stock_notes", %{}, @english))
    end

    test "keeps AshJsonApi's own sentence for a record that is not there" do
      assert %{"detail" => "No note record found with `id: " <> _} =
               reply(:get, missing_note(), nil, @english)
    end
  end

  describe "an app that never set the request's language" do
    test "answers a missing required value as AshJsonApi wrote it" do
      assert %{"code" => "required", "detail" => "is required", "meta" => %{}} =
               reply_without_the_plug(:post, "/notes", %{}, @russian)
    end

    test "answers a required error Ash itself raised in the actor's language" do
      {:error, error} = Ash.create(AshGettextFixture.Api.Note, %{}, actor: @russian)

      assert [%{code: "required", detail: "обязательное поле", meta: %{translation: _}}] =
               AshJsonApi.Error.to_json_api_errors(
                 Api,
                 AshGettextFixture.Api.Note,
                 error,
                 :create
               )
    end

    test "still answers a validation in the actor's language" do
      assert %{"detail" => "Вес должен быть не менее 30 кг"} =
               reply_without_the_plug(:post, "/notes", %{title: "t", weight: 5}, @russian)
    end

    test "answers a record that is not there as AshJsonApi wrote it" do
      assert %{"detail" => "No note record found with `id: " <> _} =
               reply_without_the_plug(:get, missing_note(), nil, @russian)
    end
  end

  describe "a request with no actor" do
    test "gets AshJsonApi's own text" do
      assert %{"code" => "required", "detail" => "is required"} =
               reply(:post, "/notes", %{}, nil)
    end
  end

  describe "an actor whose language has no catalog" do
    test "gets the source language" do
      assert %{"detail" => "is required"} = reply(:post, "/notes", %{}, %{language: "de"})
    end
  end

  describe "a domain with no error handler of its own" do
    test "gets the translating handler without asking for it" do
      assert AshJsonApi.Domain.Info.error_handler(Api) ==
               {AshGettext.JsonApi, :translate_error, []}
    end
  end

  describe "a domain that switched error translation off" do
    test "keeps the handler it had: none" do
      assert AshJsonApi.Domain.Info.error_handler(AshGettextFixture.StockApi) == nil
    end

    test "replies as AshJsonApi does on its own, even to a Russian reader" do
      assert %{"code" => "required", "detail" => "is required"} =
               reply(:post, "/stock_notes", %{}, @russian, AshGettextFixture.StockApi)
    end
  end

  describe "an app with its own error handler" do
    test "has it run first, with its own arguments" do
      assert AshJsonApi.Domain.Info.error_handler(AshGettextFixture.OwnHandlerApi) ==
               {AshGettext.JsonApi, :translate_error,
                [{AshGettextFixture.OwnHandler, :handle_error, ["S-1"]}]}
    end

    test "keeps what it added to meta, next to the translated sentence" do
      assert %{"detail" => "обязательное поле", "meta" => %{"support_code" => "S-1"}} =
               reply(:post, "/own_notes", %{}, @russian, AshGettextFixture.OwnHandlerApi)
    end

    test "keeps the error's own values in meta too" do
      assert %{"meta" => %{"support_code" => "S-1", "min" => 30}} =
               reply(
                 :post,
                 "/own_notes",
                 %{title: "t", weight: 5},
                 @russian,
                 AshGettextFixture.OwnHandlerApi
               )
    end
  end

  describe "translate_error/2" do
    defp error(fields \\ []) do
      struct!(
        %AshJsonApi.Error{
          id: "id-1",
          status_code: 400,
          code: "required",
          title: "Required",
          detail: "is required",
          source_pointer: "/data/attributes/title",
          meta: %{by: "the app"}
        },
        fields
      )
    end

    defp in_russian(fun), do: Gettext.with_locale(Backend, "ru", fun)

    test "changes the detail and nothing else" do
      translated =
        in_russian(fn -> AshGettext.JsonApi.translate_error(error(), %{domain: Api}) end)

      assert translated == %{error() | detail: "обязательное поле"}
    end

    test "leaves an error with no detail alone" do
      blank = error(detail: nil)

      assert in_russian(fn -> AshGettext.JsonApi.translate_error(blank, %{domain: Api}) end) ==
               blank
    end

    test "leaves an error with no meta alone but for its detail" do
      bare = error(meta: nil)

      assert in_russian(fn -> AshGettext.JsonApi.translate_error(bare, %{domain: Api}) end) ==
               %{bare | detail: "обязательное поле"}
    end

    test "leaves an unknown code with an untranslated detail alone" do
      unknown = error(code: "brand_new_in_the_next_ash", detail: "a sentence Ash added later")

      assert in_russian(fn -> AshGettext.JsonApi.translate_error(unknown, %{domain: Api}) end) ==
               unknown
    end

    test "leaves the error alone for a domain with no gettext block" do
      assert in_russian(fn ->
               AshGettext.JsonApi.translate_error(error(), %{
                 domain: AshGettextFixture.Untranslated
               })
             end) == error()
    end

    test "leaves the error alone for a domain that switched error translation off" do
      assert in_russian(fn ->
               AshGettext.JsonApi.translate_error(error(), %{
                 domain: AshGettextFixture.SwitchedOff
               })
             end) == error()
    end

    test "leaves the error alone when the context names no domain" do
      assert in_russian(fn -> AshGettext.JsonApi.translate_error(error(), %{}) end) == error()

      assert in_russian(fn -> AshGettext.JsonApi.translate_error(error(), %{domain: nil}) end) ==
               error()
    end

    test "passes anything that is not a JSON:API error through" do
      assert AshGettext.JsonApi.translate_error(:not_an_error, %{domain: Api}) == :not_an_error
    end
  end

  describe "the plug" do
    defp through_plug(actor, domain \\ Api) do
      conn(:get, "/")
      |> Ash.PlugHelpers.set_actor(actor)
      |> AshGettext.Plug.call(AshGettext.Plug.init(domain: domain))
    end

    test "sets the actor's language, as the domain's resolver answers it" do
      through_plug(@russian)

      assert Gettext.get_locale(Backend) == "ru"
    end

    test "puts the language back once the reply is sent" do
      before = Gettext.get_locale(Backend)

      @russian |> through_plug() |> send_resp(200, "")

      assert Gettext.get_locale(Backend) == before
    end

    test "leaves the language alone with no actor" do
      Gettext.put_locale(Backend, "ru")

      through_plug(nil)

      assert Gettext.get_locale(Backend) == "ru"
    end

    test "leaves the language alone for a domain with no gettext block" do
      before = Gettext.get_locale(Backend)

      through_plug(@russian, AshGettextFixture.Untranslated)

      assert Gettext.get_locale(Backend) == before
    end

    test "returns the conn it was given" do
      conn = conn(:get, "/") |> Ash.PlugHelpers.set_actor(nil)

      assert AshGettext.Plug.call(conn, AshGettext.Plug.init(domain: Api)) == conn
    end

    test "raises at init without a domain" do
      assert_raise KeyError, fn -> AshGettext.Plug.init([]) end
    end
  end
end
