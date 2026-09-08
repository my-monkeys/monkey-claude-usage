# CLAUDE.md — `monkey-claude-usage`

App macOS de barre de menus : la consommation Claude de **plusieurs comptes** à la fois.
Swift 6 / SwiftPM, macOS 14+, open source (BSD-2), repo public `my-monkeys/monkey-claude-usage`,
cask `my-monkeys/tap/monkey-claude-usage`.

Dérivée de `jeremy-prt/claude-usage-mini` (elle-même de `Blimp-Labs/claude-usage-bar`) — la
chaîne d'attribution est dans `LICENSE` et le README, **ne pas la retirer**.

## Commandes

```bash
swift test                 # 11 tests (parsing, compte à rebours, historique)
swift build                # les deux targets
./scripts/build-dmg.sh     # dist/Monkey Claude Usage.app + dist/MonkeyClaudeUsage-<v>.dmg
./scripts/release.sh 1.0.0 # signe, notarise, tag, release GitHub, met à jour le cask
```

Il n'y a **pas** de linter configuré : `swift build` doit sortir sans avertissement.

## ⚠️ L'API a changé de forme — c'est tout le sujet du projet

`GET https://api.anthropic.com/api/oauth/usage` (en-têtes `Authorization: Bearer <token>` et
`anthropic-beta: oauth-2025-04-20`) ne décrit plus ses limites par des champs fixes. Les
anciens champs existent encore mais **`seven_day_opus` et `seven_day_sonnet` valent `null`** ;
les fenêtres par modèle ne vivent plus que dans le tableau `limits` :

```json
{"kind":"weekly_scoped","group":"weekly","percent":54,"severity":"normal",
 "resets_at":"2026-09-14T18:00:00.435695+00:00",
 "scope":{"model":{"id":null,"display_name":"Fable"}},"is_active":true}
```

D'où `UsagePayload` : le tableau gagne dès qu'il est non vide, les champs fixes ne servent
que de repli. **Ne jamais coder en dur une liste de modèles** — la réponse porte aussi des
clés inertes (`tangelo`, `nimbus_quill`, `iguana_necktie`…) qui sont ignorées.

⚠️ `resets_at` a **six** décimales de seconde. Les parseurs ISO-8601 stricts les rejettent
selon la version du système : `ISO8601.date(from:)` essaie avec et sans fraction, puis
tronque. Ne pas « simplifier » en un seul formateur.

## ⚠️ Le multi-compte tient à un détail de navigateur

Chaque compte a son propre flux PKCE et son propre item de trousseau
(`fr.mymonkey.monkeyclaudeusage.credentials`, clé = UUID du compte). Mais la page
d'autorisation utilise la **session du navigateur** : ajouter un second compte sans s'être
déconnecté de Claude redonne un jeton du **même** compte. `AppState.completeSignIn` s'en
aperçoit et rafraîchit l'onglet existant au lieu d'en créer un doublon — mais l'utilisateur
croit avoir ajouté un compte. D'où le texte d'avertissement dans le popover et les
réglages : **ne pas l'enlever**.

⚠️ **Le profil se lit sur `GET /api/oauth/profile`, pas sur `/userinfo`** — ce dernier
répond **404** (c'est ce que faisait le projet amont, d'où des comptes toujours anonymes).
La réponse porte `account.uuid`, stable, sur lequel se fait la déduplication ; l'e-mail
n'est qu'un repli, il peut changer. Elle porte aussi `organization.rate_limit_tier`
(`default_claude_max_20x` → « Max 20× »), affiché à côté du compte.

## ⚠️ Ne pas « importer » la session de Claude Code

Tentant, et écarté sciemment : le CLI garde ses jetons dans l'item de trousseau
`Claude Code-credentials`, qu'on saurait lire. Mais **le jeton de rafraîchissement serait
alors partagé entre deux propriétaires** : au premier renouvellement, celui qui ne l'a pas
fait se retrouve avec un jeton périmé. Concrètement, l'app peut **déconnecter `claude`**,
ou l'inverse, sans que l'utilisateur fasse le lien. S'en tenir à un flux OAuth par compte.

## Rendu de la barre de menus

`MenuBarIcon.swift` dessine une `NSImage` en `isTemplate = true` (donc monochrome, macOS
gère le contraste). Trois règles qui ne se devinent pas :

- **Les lignes sont partagées entre comptes** pour que les barres s'alignent verticalement.
  Un compte qui n'a pas une fenêtre reçoit une barre en pointillés.
- **Un compte n'a des étiquettes de ligne (`5h`/`7d`/`Fa`) que s'il est seul.** À plusieurs,
  la place passe à une lettre par compte et l'ordre des lignes fait foi.
- **Une limite saturée remplace les barres du compte par un compte à rebours** (`Fa 2j`).
  C'est voulu : une barre pleine ne dit rien, l'heure de reset si. Le budget est de quatre
  caractères — d'où `Countdown.short`, testé pour ça.

La hauteur utile est de 18 pt : `Metrics.rowGeometry` réduit la hauteur des barres quand il y
a plus de trois fenêtres. Au-delà de cinq, ça devient illisible — préférer alors le popover.

## Deux historiques, et un seul est rattachable à un compte

⚠️ **L'API ne renvoie aucun historique** — seulement un niveau instantané. D'où deux sources,
qu'il ne faut pas confondre :

1. **Quota, par compte** — chaque relevé réussi est ajouté à
   `~/Library/Application Support/fr.mymonkey.monkeyclaudeusage/history/<uuid>.json`, élagué
   à l'écriture. Vide à l'installation, et incapable de montrer une période où l'app ne
   tournait pas : le dire plutôt que de laisser croire à un bug. C'est ce qui alimente les
   barres de session (`ConsumptionSeries`) et les lignes hebdomadaires (`LevelSeries`).
2. **Activité locale, sans compte** — `LocalActivityStore` lit les transcriptions de Claude
   Code sous `~/.claude/projects/**/*.jsonl`. Trois mois d'historique réel, disponibles dès
   la première ouverture.

⚠️ **Les transcriptions ne portent aucun identifiant de compte** (vérifié : ni `account`, ni
`org`, ni e-mail). L'activité locale est donc **volontairement hors des onglets de compte** —
la rattacher à l'onglet sélectionné serait un mensonge. Ne pas « améliorer » ça.

⚠️ Trois pièges de performance, tous mesurés sur 1,7 Go de transcriptions :
- `ISO8601DateFormatter` alloué par appel coûtait **35 s** sur 96 000 lignes. D'où
  `Date.ISO8601FormatStyle`, qui est une valeur `Sendable` construite une fois.
- Accumuler dans un `Data` puis le re-trancher recopie le reste à chaque ligne (O(n²)) :
  50 s. D'où le fichier mappé parcouru au `memchr`/`memmem`.
- **Chaque message assistant est écrit deux fois** dans sa transcription — 46 945 doublons
  sur 48 608 identifiants. Sans déduplication, tous les chiffres sont doublés. L'empreinte
  est un FNV-1a et non `hashValue`, qui est resemé à chaque lancement et invaliderait le cache.

Bilan : 10 s au premier balayage, 0,1 s ensuite.

## Session et semaine ne partagent pas de repère

La fenêtre de session tourne cinq fois par jour, les hebdomadaires une fois par semaine. Sur
une échelle commune, celle qui bouge le moins est écrasée. D'où deux formes distinctes dans
`QuotaHistoryView` : **barres de consommation** pour la session (points de quota brûlés par
seau), **ligne de niveau** pour chaque fenêtre hebdomadaire.

⚠️ Une baisse de niveau entre deux relevés est un **reset**, pas une consommation négative.
`ConsumptionSeries` la traite comme telle, marque la frontière, et laisse **vides** les seaux
que l'app n'a pas observés plutôt que d'étaler un saut sur des heures où il n'a pas eu lieu.

⚠️ `BarMark(x:unit:)` avec `.second` donne des barres larges d'une seconde, donc invisibles.
Un seau de quinze minutes n'étant pas une unité de calendrier, les barres se posent en
`xStart`/`xEnd`.

## Verre liquide (macOS 26+)

`UI/LiquidGlass.swift` va chercher `glassEffect` derrière `#available(macOS 26, *)` plutôt que
de relever la cible de déploiement — une utilitaire de barre de menus est précisément ce qu'on
garde sur une machine ancienne.

⚠️ **Le verre échantillonne la fenêtre derrière lui.** Là où il n'y a rien à échantillonner,
l'effet ne rend **rien du tout** : un onglet devient invisible. D'où le fond plein toujours
posé, le verre seulement par-dessus. Et `GlassEffectContainer` fait disparaître tout son
contenu dans un rendu hors écran — il n'est pas utilisé.

Les contrôles standard gardent leur style système : ils prennent le nouveau look tout seuls
une fois compilés contre le SDK Tahoe.

## Séparation des targets

`MonkeyClaudeUsageCore` n'importe **pas** AppKit ni SwiftUI : c'est ce qui rend les jetons,
le parsing et les dates testables sans écran. Corollaire : `OAuthClient` ne fait qu'engendrer
l'URL d'autorisation, c'est l'UI qui l'ouvre. Ne pas y glisser de `NSWorkspace`.

## Signature et release

Certificat `Developer ID Application: Maxim Costa (5C67TFSJ2B)` dans le trousseau local.
**Aucun secret côté GitHub Actions** : la CI se limite à `swift build` + `swift test`, la
release se fait depuis le Mac. Config de notarisation dans `.release.env` (non commité) —
voir `docs/RELEASING.md`.
