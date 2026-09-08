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
4. signature EdDSA du DMG (`sign_update`), `appcast.xml` réécrit avec la nouvelle
   entrée, commité et poussé — voir « Mises à jour » ci-dessous ;
5. tag `vX.Y.Z` poussé, release GitHub créée avec les commits depuis le tag
   précédent, DMG attaché ;
6. cask `Casks/monkey-claude-usage.rb` réécrit dans `my-monkeys/homebrew-tap`
   (version + sha256), commité, poussé.

Chaque étape est idempotente : relancer après un échec reprend là où ça s'est
arrêté (tag déjà posé, DMG déjà agrafé, release existante → asset remplacé,
cask déjà à jour → rien).

Deux options :

- `--dry-run` : construit et notarise, mais ne pose ni tag, ni release, ni
  commit de cask. Affiche le diff du cask qu'il aurait écrit.
- `--skip-notarize` : saute Apple entièrement. Pour une répétition rapide
  (`--dry-run --skip-notarize`), **jamais pour une vraie publication**.

## Mises à jour

L'app se met à jour toute seule avec **Sparkle 2**. Le flux est
`SUFeedURL` → `appcast.xml` → DMG de la release GitHub ; il n'y a **rien à
héberger**, le fichier est servi par `raw.githubusercontent.com` depuis la
branche par défaut :

```
https://raw.githubusercontent.com/my-monkeys/monkey-claude-usage/main/appcast.xml
```

### La clé privée

La paire EdDSA a été engendrée une fois avec l'outil de Sparkle. **La clé privée
vit dans le trousseau de session**, et nulle part ailleurs — jamais dans ce dépôt,
jamais dans `.release.env` :

- service `https://sparkle-project.org`, compte **`monkey-claude-usage`** ;
- la clé publique correspondante, `OCHtXohyD4woD+VjFfZvJRg8RDas5ZAXK4UlGHLRIvQ=`,
  est posée en `SUPublicEDKey` dans l'`Info.plist` par `scripts/build-app.sh`.

⚠️ **Le compte n'est pas celui par défaut.** Le trousseau contient déjà une clé
sous le compte `ed25519`, qui n'est pas celle-ci : oublier `--account
monkey-claude-usage` signe avec la mauvaise clé, et **tous les clients rejettent
la mise à jour** sans que rien ne le signale côté serveur. `release.sh` compare
donc la clé publique du trousseau à celle embarquée dans l'app avant de signer, et
s'arrête si elles diffèrent.

⚠️ **Perdre le trousseau, c'est perdre la capacité de publier une mise à jour** :
les apps installées ne reconnaîtront plus rien de ce qu'on signe ensuite, et il
faudra les réinstaller à la main. La sauvegarder :

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account monkey-claude-usage -x cle.txt
# ranger cle.txt dans le gestionnaire de mots de passe, puis l'effacer du disque
```

### Les outils Sparkle ne sont pas dans le `PATH`

Ils arrivent avec la dépendance SwiftPM, sous
**`.build/artifacts/sparkle/Sparkle/bin/`** (`generate_keys`, `sign_update`,
`generate_appcast`). Un `swift package resolve` suffit à les faire apparaître ;
`release.sh` s'arrête avec un message clair s'ils manquent.

⚠️ **Le premier `sign_update` ouvre une fenêtre du trousseau** — « sign_update
souhaite accéder à la clé… ». C'est normal : la clé a été créée par
`generate_keys`, qui est le seul outil autorisé au départ. Répondre **« Toujours
autoriser »** une fois ; sinon `release.sh` reste bloqué là, sans message.

### Ce que `release.sh` ajoute

Entre la notarisation et la release GitHub :

1. lit `CFBundleVersion` et `SUPublicEDKey` **dans l'app construite** — pas dans une
   seconde copie des règles — et refuse de continuer si la clé n'est pas celle du
   trousseau ;
2. `sign_update -p --account monkey-claude-usage <dmg>` → la signature EdDSA ;
3. `scripts/update-appcast.py` insère l'entrée en tête de `appcast.xml` (version,
   `shortVersionString`, URL du DMG de la release, longueur, signature,
   `sparkle:minimumSystemVersion` 14.0). Relancer avec la même version **remplace**
   l'entrée au lieu d'en ajouter une seconde ;
4. commit `chore: appcast for X.Y.Z` et push.

`--dry-run` n'écrit rien : il affiche le diff qu'il aurait appliqué, exactement
comme pour le cask.

⚠️ **`CFBundleVersion` est un entier, pas la version marketing.** Sparkle compare
ce champ, et « 0.10.0 » doit passer devant « 0.2.0 » — ce que la chaîne ne fait
pas. `build-app.sh` calcule donc `major × 10000 + minor × 100 + patch` (0.1.0 →
`100`, 1.0.0 → `10000`) et **s'arrête si `minor` ou `patch` atteint 100**, ce qui
casserait l'ordre.

⚠️ **Un échec en cours de route puis une relance change le DMG** (`hdiutil` n'est
pas reproductible), donc la signature, donc `appcast.xml`, donc un nouveau commit —
alors que le tag pointe déjà l'ancien. Le script s'arrête sur « tag already exists
and points elsewhere » : supprimer le tag (`git tag -d vX.Y.Z && git push --delete
origin vX.Y.Z`) et relancer.

⚠️ **Les installations en 0.1.0 ne se mettront pas à jour toutes seules** : cette
version est antérieure à Sparkle, elle ne va donc chercher aucun flux. Il leur faut
un `brew upgrade --cask monkey-claude-usage` (ou un DMG) une fois. L'entrée 0.1.0
dans l'appcast n'est là que pour que le flux raconte l'historique complet.

### Vérifier qu'une mise à jour est bien proposée

Sans attendre une vraie release, en servant un faux flux en local. Le point qui
fait foi est la requête vers `sparkle:releaseNotesLink` : Sparkle ne va chercher les
notes **que** s'il a accepté l'entrée et affiche la fenêtre de mise à jour.

```bash
# 1. une version « neuve » à proposer
VERSION=0.9.9 ./scripts/build-dmg.sh
SIG=$(.build/artifacts/sparkle/Sparkle/bin/sign_update -p --account monkey-claude-usage \
        dist/MonkeyClaudeUsage-0.9.9.dmg)

# 2. un flux local qui la décrit (ajouter à la main un
#    <sparkle:releaseNotesLink>http://localhost:8765/notes.html</sparkle:releaseNotesLink>)
mkdir -p /tmp/feed && cp dist/MonkeyClaudeUsage-0.9.9.dmg /tmp/feed/
echo '<html><body>notes</body></html>' > /tmp/feed/notes.html
cp appcast.xml /tmp/feed/
python3 scripts/update-appcast.py --appcast /tmp/feed/appcast.xml \
  --version 0.9.9 --build 999900 --url http://localhost:8765/MonkeyClaudeUsage-0.9.9.dmg \
  --length "$(stat -f%z dist/MonkeyClaudeUsage-0.9.9.dmg)" --signature "$SIG"
(cd /tmp/feed && python3 -m http.server 8765 --bind 127.0.0.1)

# 3. une app « ancienne » qui pointe ce flux
VERSION=0.1.0 ./scripts/build-app.sh
cp -R "dist/Monkey Claude Usage.app" /tmp/old.app
/usr/libexec/PlistBuddy -c "Set :SUFeedURL http://localhost:8765/appcast.xml" /tmp/old.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" /tmp/old.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" /tmp/old.app/Contents/Info.plist
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Maxim Costa (5C67TFSJ2B)" /tmp/old.app
defaults delete fr.mymonkey.monkeyclaudeusage SULastCheckTime
open -n /tmp/old.app
```

⚠️ **`NSAllowsLocalNetworking` est indispensable** pour un flux en `http://` :
sans lui, App Transport Security refuse la connexion et Sparkle échoue en silence
— le serveur ne voit **aucune** requête, ce qui ressemble à un flux mal câblé.

Et sur la vraie release, une fois `appcast.xml` poussé :

```bash
curl -s https://raw.githubusercontent.com/my-monkeys/monkey-claude-usage/main/appcast.xml | head -20
.build/artifacts/sparkle/Sparkle/bin/sign_update --verify --account monkey-claude-usage \
  dist/MonkeyClaudeUsage-X.Y.Z.dmg '<signature du flux>'   # sort 0 si elle correspond
```

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
- **Rien ne copie `Sparkle.framework` tout seul.** Le `.app` est assemblé à la main,
  sans phase « Embed Frameworks » : `build-app.sh` va chercher le framework produit
  par SwiftPM sous `<bin-path>/Frameworks/`, le pose dans `Contents/Frameworks/` au
  `ditto` (c'est un arbre de liens symboliques autour de `Versions/B`), **et ajoute
  le `@rpath`**. SwiftPM lie `@rpath/Sparkle.framework/Versions/B/Sparkle` mais
  n'émet que ses propres rpaths (`/usr/lib/swift`, `@executable_path/../lib`) : sans
  `install_name_tool -add_rpath @executable_path/../Frameworks`, l'app meurt au
  lancement sur « Library not loaded ». Et cet ajout invalide la signature, donc il
  se fait **avant** de signer.
- **Sparkle imbrique des bundles que signer le `.framework` ne touche pas** :
  `XPCServices/Downloader.xpc`, `XPCServices/Installer.xpc`, `Autoupdate` et
  `Updater.app`. SwiftPM les livre signés **ad-hoc** ; laissés tels quels, la
  notarisation rejette tout l'envoi avec « not signed with a valid Developer ID
  certificate » — c'est ce qui était arrivé à `glance` en 1.7.0. `sign_sparkle()`
  les signe du plus profond au moins profond, avec `--options runtime --timestamp`
  et `--preserve-metadata=entitlements` pour les XPC. Le contrôle qui le prouve est
  `codesign --verify --deep --strict` : un `--verify` sans `--deep` ne descend pas
  dedans et passe au vert sur un helper non signé.
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
