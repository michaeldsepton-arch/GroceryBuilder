# Budget Basket - setup

## 1. One-time: add the signing key (required for builds)
Android only updates an app in place if every version is signed with the **same key**.
A key was generated for you in `secrets/` (git-ignored, never committed).

GitHub repo -> Settings -> Secrets and variables -> Actions -> New repository secret. Add the four
values listed in `secrets/SECRETS-TO-ADD.txt`. Keep a private backup of `secrets/budget-basket-release.jks`.

## 2. First install
After the first successful *Build & release APK* run, open the repo's **Releases** page on your phone,
download `budget-basket.apk` from the newest release and install it (allow "install unknown apps" for your browser).

## 3. Updates
Every push to `main` builds a new signed release. In the app: **More -> Check for app updates**
(it also checks automatically on launch and shows a dot on the More tab). Tap *Download & install*.
Same app id + same key = Android updates in place and keeps all your data.

## Prices
`Refresh store prices` (Actions) scrapes Red Deer stores daily and publishes `catalog.json.gz` to the
`catalog` release; the app downloads it. Run it manually from the Actions tab to test.
