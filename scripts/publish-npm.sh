#!/bin/bash
# npm'e ERLİK yayını — repo kökünden DEĞİL, public erlik-releases paketinden.
# Repodaki erlik-app eski bir derleme olabilir; npm'e giden binary, imzalı
# manifestteki sha256 ile doğrulanmış release paketiyle birebir aynı olmalı.
# Kullanım: ./publish.sh [sürüm]   (varsayılan: imzalı manifestteki son sürüm)
#           DRY_RUN=1 ./publish.sh  -> indir, doğrula, tara; yayınlama
set -euo pipefail
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
REG="https://registry.npmjs.org/"
MANIFEST_URL="https://api.erlik.be/api/update/latest"
RELEASES="https://github.com/halilertekin/erlik-releases/releases/download"
WORK="$(mktemp -d -t erlik-npm)"
trap 'rm -rf "$WORK"' EXIT

echo "🐺 ERLİK npm yayını hazırlanıyor..."
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    # GitHub Actions: npm trusted publishing (OIDC) — token yok, 2FA sorusu yok
    echo "👤 GitHub Actions trusted publishing (OIDC)"
else
    NPM_USER="$(npm whoami --registry "$REG" 2>/dev/null || true)"
    [ -n "$NPM_USER" ] || { echo "❌ npm oturumu yok: önce 'npm login' (ya da GitHub Actions 'npm-publish' iş akışı)"; exit 1; }
    echo "👤 npm kullanıcısı: $NPM_USER"
fi

# 1. İmzalı manifest: sürüm ve beklenen sha256 (ayrı kaynak: api.erlik.be)
curl -fsS "$MANIFEST_URL" -o "$WORK/manifest.json" || { echo "❌ manifest alınamadı: $MANIFEST_URL"; exit 1; }
LATEST="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$WORK/manifest.json")"
VER="${1:-$LATEST}"
[ "$VER" = "$LATEST" ] || { echo "❌ npm yalnız son yayınlanan sürümle eşitlenir ($LATEST), istenen: $VER"; exit 1; }
EXPECTED_SHA="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha256"])' "$WORK/manifest.json")"
if [ -z "${DRY_RUN:-}" ] && npm view "erlik@$VER" version --registry "$REG" >/dev/null 2>&1; then
    echo "ℹ️  erlik@$VER npm'de zaten var, yayın atlandı."; exit 0
fi

# 2. Release paketini indir ve doğrula
TARBALL="erlik-$VER-macos-arm64.tar.gz"
curl -fsSL "$RELEASES/v$VER/$TARBALL" -o "$WORK/$TARBALL"
SHA="$(shasum -a 256 "$WORK/$TARBALL" | cut -d' ' -f1)"
[ "$SHA" = "$EXPECTED_SHA" ] || { echo "❌ sha256 uyuşmuyor: $SHA != $EXPECTED_SHA"; exit 1; }
echo "✅ paket doğrulandı ($TARBALL, sha256 ${SHA:0:12}…)"

PKG="$WORK/pkg"; mkdir -p "$PKG"
tar -xzf "$WORK/$TARBALL" -C "$PKG"
cp "$ROOT/npm-README.md" "$PKG/README.md"
PKG_VER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$PKG/package.json")"
[ "$PKG_VER" = "$VER" ] || { echo "❌ paketteki package.json sürümü $PKG_VER (beklenen $VER)"; exit 1; }

# 3. Özel altyapı taraması kaynak repodaki sürüm betiğinde, paket yüklenmeden önce yapılır;
#    burada yalnız imzalı manifestteki sha256 ile birebir aynı paket yayınlanır.

# 4. Deneme + gerçek yayın
(cd "$PKG" && npm publish --dry-run --registry "$REG" 2>&1 | grep -E "total files|package size" || true)
if [ -n "${DRY_RUN:-}" ]; then echo "🧪 DRY_RUN: doğrulama tamam, yayın yapılmadı."; exit 0; fi
(cd "$PKG" && npm publish --access public --registry "$REG")
echo "✅ erlik@$VER npm'de yayında: https://www.npmjs.com/package/erlik"
