# Publier une version

La release se fait **en local, depuis le Mac**. La CI GitHub ne fait que
`swift build` + `swift test` : aucun secret n'y est configuré, elle ne peut donc
ni signer ni notariser.

```bash
./scripts/release.sh 1.2.3
```

## Configuration, une fois pour toutes

### Le certificat

`Developer ID Application: Maxim Costa (5C67TFSJ2B)` doit être dans le trousseau.
Les scripts prennent automatiquement le premier certificat « Developer ID
Application » qu'ils trouvent ; pour en forcer un autre, poser
`CODESIGN_IDENTITY`.

```bash
security find-identity -v -p codesigning | grep 'Developer ID Application'
```

Sans certificat, `build-app.sh` signe en ad-hoc et le dit : l'app tourne sur ce
Mac, nulle part ailleurs.

### La notarisation

Créer `.release.env` à la racine (déjà dans `.gitignore`, **ne jamais le
committer**) :

```sh
NOTARY_KEY_ID=XXXXXXXXXX
NOTARY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NOTARY_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

Le `KEY_ID` est celui qui figure dans le nom du fichier `.p8` — il y a plusieurs
clés dans `~/.appstoreconnect/private_keys/`, prendre celle qui a le droit
*Developer*. L'`ISSUER_ID` se lit dans App Store Connect › Users and Access ›
Integrations › Team Keys : c'est le même pour toutes les clés de l'équipe.

Variante : ranger les identifiants dans le trousseau une bonne fois, et ne
garder qu'un nom de profil dans `.release.env`.

```bash
xcrun notarytool store-credentials monkey-claude-usage \
  --key ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
echo 'NOTARY_PROFILE=monkey-claude-usage' >> .release.env
```

### `gh`

`gh auth status` doit répondre connecté, avec le droit d'écrire sur
`my-monkeys/monkey-claude-usage` **et** sur `my-monkeys/homebrew-tap`.

## Ce que fait `release.sh`

1. vérifie l'arbre git propre, la branche par défaut, le format `X.Y.Z` ;
2. `build-dmg.sh` → `build-app.sh` : build universel (arm64 + x86_64), montage du
   `.app`, signature `--options runtime --timestamp`, puis DMG signé ;
3. `xcrun notarytool submit --wait`, `xcrun stapler staple`, et vérification
   `spctl -a -vvv -t install` qui **doit** dire `source=Notarized Developer ID` ;
4. tag `vX.Y.Z` poussé, release GitHub créée avec les commits depuis le tag
   précédent, DMG attaché ;
5. cask `Casks/monkey-claude-usage.rb` réécrit dans `my-monkeys/homebrew-tap`
   (version + sha256), commité, poussé.

Chaque étape est idempotente : relancer après un échec reprend là où ça s'est
arrêté (tag déjà posé, DMG déjà agrafé, release existante → asset remplacé,
cask déjà à jour → rien).

Deux options :

- `--dry-run` : construit et notarise, mais ne pose ni tag, ni release, ni
  commit de cask. Affiche le diff du cask qu'il aurait écrit.
- `--skip-notarize` : saute Apple entièrement. Pour une répétition rapide
  (`--dry-run --skip-notarize`), **jamais pour une vraie publication**.

## Construire sans publier

```bash
VERSION=1.2.3 ./scripts/build-app.sh    # dist/Monkey Claude Usage.app
VERSION=1.2.3 ./scripts/build-dmg.sh    # + dist/MonkeyClaudeUsage-1.2.3.dmg
```

## Vérifier le résultat

```bash
open "dist/Monkey Claude Usage.app"
pgrep -f MonkeyClaudeUsage            # l'app est un agent : rien dans le Dock
pkill -f MonkeyClaudeUsage
```

## Les pièges

- **`LSUIElement` = pas d'icône dans le Dock.** Une app lancée qui n'apparaît
  nulle part n'est pas une app plantée : c'est un agent, il vit dans la barre de
  menus. Le seul test qui fait foi est `pgrep -f MonkeyClaudeUsage`.
- **Le build universel n'est pas dans `.build/release`** mais dans
  `.build/apple/Products/Release`. Les scripts demandent le chemin à SwiftPM
  (`--show-bin-path`) plutôt que de le supposer.
- **Le bundle de ressources SPM doit être dans `Contents/Resources/`.** C'est là
  que le `Bundle.module` engendré par SwiftPM le cherche (`Bundle.main.resourceURL`) ;
  ailleurs, il fait un `fatalError` au premier accès — donc plus tard, et pas au
  lancement, ce qui ressemble à un tout autre bug.
- **`--options runtime` est obligatoire pour la notarisation.** Sans hardened
  runtime, Apple rejette avec « The executable does not have the hardened runtime
  enabled », après avoir quand même fait attendre l'envoi complet.
- **`xattr -cr` avant de signer.** Un attribut étendu traînant (quarantaine,
  métadonnées Finder) fait échouer `codesign` sur « resource fork, Finder
  information, or similar detritus not allowed ».
- **Un DMG signé mais pas notarisé passe `codesign --verify`** et se fait quand
  même bloquer chez les autres. Ce qui départage, c'est `spctl` :
  `source=Notarized Developer ID` quand tout va bien, `rejected` +
  `source=Unnotarized Developer ID` sinon.
- **`hdiutil create` est déprécié depuis macOS 26** au profit de
  `diskutil image create`, et prévient bruyamment. Il fonctionne toujours, et
  c'est le seul des deux qui existe sur macOS 14 et 15 : on garde `hdiutil`.
- **Un volume resté monté** après un `build-dmg.sh` interrompu fait échouer
  `hdiutil` sur « Resource busy ». Le script démonte `/Volumes/Monkey Claude Usage`
  avant de reconstruire, mais un démontage manuel reste parfois nécessaire.
- **Le nom de l'app est contractuel.** Le cask installe
  `Monkey Claude Usage.app` : renommer le `.app` casse `brew install` sans que
  rien d'autre ne le signale.
- **Ne pas committer `dist/` ni `.release.env`** — les deux sont déjà ignorés.

## Après publication

```bash
brew update && brew install --cask my-monkeys/tap/monkey-claude-usage
```
