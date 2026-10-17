# PR 1842 (apps_core adoption): what belongs where

Source: https://github.com/Undeadlol1/personal-flutter-projects/pull/1842
Reviewed against ash_gettext `main` (e691c87) on 2026-10-16.

Rule used: a piece belongs in the library when it would be written the same
way by any Ash app using gettext. It belongs in the app when it knows
something only Catalyst knows (backend, where a user's locale lives, which
domains exist, how resources are grouped).

## Move into the library

- [ ] **`mix ash_gettext.install`** — `back-end/elixir/lib/mix/tasks/ash_gettext.install.ex`.
  Its logic (`AshGettext.Installer`) is already here; the app only hosts the
  shell. One tool, two repos. Move the task here. Its docs point at
  `mix ash_gettext.gen.resolver`, which does not exist anywhere — add it or
  drop the mention. Note: the task pastes a full `gettext do` block into every
  domain, which is the repetition `TranslatingBase` just removed; if it stays,
  it needs a way to emit `use <base>` instead.
- [ ] **"Every resource of a translating domain opted in" check** —
  `test/ash_gettext/translating_domains_cover_every_write_test.exs`.
  Nothing Catalyst-specific except a hand-kept domain list. Belongs here as an
  opt-in domain option (default off, Ash style); `TranslatingBase` turns it on
  once and the app test and its domain list go away. Match the transformer's
  rule: an action with its own `error_handler` is a deliberate choice, not a
  miss (the app test currently flags it).
- [ ] **Template freshness test** —
  `test/ash_gettext/extracted_template_is_current_test.exs` re-implements
  `mix ash_gettext.extract --check` (scan + `to_pot` + compare). Keep one: the
  test should call the task, or CI should run `--check`.

## Stays in the app (correct as is)

- `Catalyst.Localization.TranslatingBase` — the library's own docs prescribe a
  base domain macro for exactly this.
- `AshGettextAdapter`, `Translator`, `LocaleConfig`, `ActorLocaleReader` — the
  library refuses to know what an actor is; this is the seam.
- Resource bases carrying `AshGettext.Resource`: `AppsCore.Base`,
  `TicketAttachment`, `AI.Base`, `Ownership.OwnerOnly(+Synced)`,
  `PhysicalHealth.DailyLog`, `FlashCards.Base`.
- Credo rules: `AshGettextResourceOptIn` + `ModuleIndex` (reads the app's
  source layout), the `NoDefInAshDomain` change (needed because
  `TranslatingBase` hides `use Ash.Domain`), `NoAshGettextInternalsInCatalystTests`,
  `NoHandRolledActorLocaleFallback`, `NoTranslationMissByComparison`.
- `normalize_items.ex` "is repeated: %{repeated}" + `.pot`/`.po` entries.
- `translated_errors_test.exs` (apps_core, bite_sized_learning, flash_cards) —
  assert rendered text through the app's API. Right shape.

## Repetition inside the app (fix in the app, not the library)

- [ ] `TranslatingBase` repeats two library defaults: `default_locale "en"` and
  `text_domain("ash_errors")`. Delete both lines.
- [ ] The resolver list `[AshGettext.Locale.Context, AshGettextAdapter]` is
  written in `TranslatingBase` and again in `Translator.resolve_locale/1`.
  One definition.
- [ ] Default locale: `"en"` literal in `TranslatingBase`,
  `LocaleConfig.default_locale()` in `Translator`. One source.
- [ ] Supported locales: `LocaleConfig` hardcodes `["en", "ru"]`; the library
  derives them from the catalogs on disk (`AshGettext.known_locales/1`). Two
  sources of truth; `LocaleConfig.supported_locales/0` can read the backend.
- [ ] `AshGettext.Resource` is now listed by hand in five base macros (plus
  `card_import.ex`, which still writes its header by hand). The PR says "no
  resource lists it", but every base does. One `Catalyst.Resource` macro the
  bases build on would hold `otp_app`, `authorizers` and the extension once.
- [ ] The three-domain list `[AppsCore, BiteSizedLearning, FlashCards]` is
  written in two test files. Goes away with the library check above;
  otherwise keep one list.
- [ ] `apps_core/translated_errors_test.exs` has 21 near-identical rows
  proving "неверное значение" per resource. That is the structural guarantee
  the library check gives for free; keep only the rows with a real message
  (priority tournament).

## Finding worth knowing (not a PR blocker)

`AshGettextResourceOptIn` only reads `use Ash.Resource` options written
literally. `AppsCore.Base`, `AI.Base`, `OwnerOnly` and `DailyLog` build them
with `unquote(...)`, so for every resource on those bases the rule gets
`domain: nil` and silently skips. Verified by running the rule on fixtures:
literal base → flagged, `unquote` bases → not flagged. Today nothing is missed
(all four bases include the extension); a future base that forgets would not
be caught by credo. The compiled-truth check above is what actually
guarantees coverage.
