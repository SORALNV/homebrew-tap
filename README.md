# SORALNV Tap

SORALNV の自作アプリ配布用 Homebrew Tap。**GitHub Releases + Tap の自動更新**で、
利用側のMacは標準Homebrewコマンドだけでインストール・更新が完結します
(clone・ビルドツール不要)。

## 使い方

```bash
# 初回インストール
brew tap SORALNV/tap
brew install SORALNV/tap/myvnc      # GUI/CLIが自動判別されるFormula
brew install SORALNV/tap/disk-smi

# 更新
brew update && brew upgrade

# 常駐サービス系 (MyVNCなど)
brew services start SORALNV/tap/myvnc
```

## 収録アプリ

| Formula | 種別 | 説明 | ソース |
|---|---|---|---|
| `myvnc` | CLI (サーバー) | ライブ画面ビューア (MJPEG, トークン認証, Tailscale限定バインド) | [SORALNV/MyVNC](https://github.com/SORALNV/MyVNC) |
| `disk-smi` | CLI | SSDのS.M.A.R.T.状態ビューア | [SORALNV/disk-smi](https://github.com/SORALNV/disk-smi) |

## 自動更新の仕組み

```
開発PC: git tag v0.x.y && git push --tags
  └─ ソースリポジトリの GitHub Actions「Release」
       ├─ ビルド/パッケージング + SHA256計算
       ├─ GitHub Releases へ公開 (dist/*, formula-update.txt)
       └─ (任意) repository_dispatch で即時通知
  └─ このtapの GitHub Actions「update-formulas」
       ├─ 15分ごと or dispatch トリガー
       ├─ apps.json の各アプリについて最新リリースタグを確認
       ├─ タグが変わっていれば Formula の url/sha256 を書き換え
       └─ ruby -c で構文検証してコミット&push
```

- **認証不要**: tap側は公開リポジトリのAPIをpollingするだけなので、
  クロスリポジトリ用のPATやGitHub Appは不要です
  (即時反映にしたい場合は `repository_dispatch` + `TAP_PAT` を後から足せる設計)。
- **新アプリの追加手順**:
  1. アプリのリポジトリにタグpushで動く Release ワークフローを置く
  2. このtapに `Formula/<app>.rb` を追加 (sha256は仮値でOK)
  3. `apps.json` に1行追加
  → 以降はタグを切るだけでTapが追従します

## バージョン固定・ロールバック

Homebrewは旧バージョンの保持を保証しないため、ロールバックはtapのgit履歴を使う:

```bash
cd "$(brew --repository SORALNV/tap)"
git log --oneline -- Formula/myvnc.rb     # 履歴確認
git checkout <commit> -- Formula/myvnc.rb # 旧バージョンのformulaへ戻す
brew reinstall SORALNV/tap/myvnc
```

もしくは特定タグのソースから直接:

```bash
brew install --build-from-source <旧タグのtarball URL>
```

設定ファイル・ユーザーデータは更新で削除されません:

- `myvnc`: トークンは `$(brew --prefix)/etc/myvnc/config.json`、フレームは
  `$(brew --prefix)/var/myvnc/frames` — Cellar外に置かれるため
  `brew upgrade` / `reinstall` / `uninstall` でも保持されます
- `disk-smi`: 設定なし (状態を持たないCLI)
