#!/usr/bin/env bash
#
# Build y deploy de sanna-ui-rc (Vite library mode + React).
# Equivalente al flujo Angular anterior: bump de versión, build, rama build, tag, push.
#
# Uso (desde la raíz de sanna-ui-rc):
#   ./build-and-deploy.sh [patch|minor|major]
#
# Requisitos: git, node, npm, remoto origin configurado.
#
# Variables opcionales:
#   VERSION_COMMIT_BRANCH  Rama donde commitear el bump de versión (por defecto: la rama actual al ejecutar el script).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "vite.config.ts" ]; then
  print_error "Ejecuta este script desde la raíz del paquete sanna-ui-rc (debe existir vite.config.ts)."
  exit 1
fi

if ! node -e "const p=require('./package.json'); process.exit(p.name==='sanna-ui-rc'?0:1)" 2>/dev/null; then
  print_error "package.json debe tener \"name\": \"sanna-ui-rc\"."
  exit 1
fi

VERSION_TYPE="${1:-patch}"

case "$VERSION_TYPE" in
  patch|minor|major) ;;
  *)
    print_error "Tipo de versión inválido. Usa: patch, minor o major"
    exit 1
    ;;
esac

print_message "Iniciando build y deploy de sanna-ui-rc..."

# --- 1. Limpiar build anterior ---
print_message "Limpiando dist/..."
rm -rf dist/

# --- 2. Dependencias ---
if [ ! -d "node_modules" ]; then
  print_message "Instalando dependencias..."
  npm install
fi

# --- 3. Bump de versión en package.json de la raíz ---
print_message "Incrementando versión ($VERSION_TYPE)..."
CURRENT_VERSION="$(node -p "require('./package.json').version")"
print_message "Versión actual: $CURRENT_VERSION"

IFS='.' read -r MAJOR MINOR PATCH <<<"$CURRENT_VERSION"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

case "$VERSION_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
print_message "Nueva versión: $NEW_VERSION"

node -e "
const fs = require('fs');
const p = JSON.parse(fs.readFileSync('package.json', 'utf8'));
p.version = '$NEW_VERSION';
fs.writeFileSync('package.json', JSON.stringify(p, null, 2) + '\n');
"

if [ -f "package-lock.json" ]; then
  print_message "Sincronizando package-lock.json con la nueva versión..."
  npm install --package-lock-only --ignore-scripts
fi

# --- 4. Build librería (Vite) ---
print_message "Ejecutando npm run build..."
npm run build

# --- 5. Verificar artefactos Vite ---
if [ ! -f "dist/sanna-ui-rc.es.js" ] || [ ! -f "dist/sanna-ui-rc.cjs.js" ]; then
  print_error "Faltan los bundles JS en dist/ (sanna-ui-rc.es.js / sanna-ui-rc.cjs.js)."
  exit 1
fi

if [ ! -f "dist/src/index.d.ts" ]; then
  print_error "No se encontró dist/src/index.d.ts (declaraciones TypeScript)."
  exit 1
fi

print_message "Build OK: JS + tipos en dist/"

# --- 6. Staging del artefacto publicable (plano, sin carpeta dist/) ---
STATE_DIR="$(mktemp -d)"
STAGING="$STATE_DIR/artifact"
mkdir -p "$STAGING"
print_message "Staging de publicación: $STAGING"

print_message "Copiando contenido de dist/..."
cp -R dist/. "$STAGING/"

print_message "Generando package.json para publicación (rutas planas)..."
node scripts/gen-publish-package.mjs "$STAGING/package.json"

if [ -f ".npmignore" ]; then
  cp -f .npmignore "$STAGING/.npmignore"
fi

# --- 7. Rama build con worktree (misma idea que el script Angular) ---
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
print_message "Rama de trabajo actual: $CURRENT_BRANCH"

ORIGINAL_DIR="$SCRIPT_DIR"
BUILD_WORKTREE="$(mktemp -d)"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  print_error "No es un repositorio git. Inicializa git y añade origin antes de desplegar."
  rm -rf "$STATE_DIR"
  exit 1
fi

if git ls-remote --heads origin build 2>/dev/null | grep -q build; then
  print_message "Rama remota build encontrada, creando worktree..."
  TEMP_BRANCH="temp-build-$(date +%s)"
  git worktree add --track -b "$TEMP_BRANCH" "$BUILD_WORKTREE" origin/build
  echo "$TEMP_BRANCH" >"$STATE_DIR/temp-branch-name"
else
  print_message "Rama build no existe en origin; se creará con el primer push."
  git worktree add --detach "$BUILD_WORKTREE"
  (
    cd "$BUILD_WORKTREE"
    git switch --orphan build 2>/dev/null || git checkout --orphan build
    git rm -rf . 2>/dev/null || true
  )
fi

cd "$BUILD_WORKTREE" || {
  print_error "No se pudo entrar al worktree"
  rm -rf "$STATE_DIR" "$BUILD_WORKTREE"
  exit 1
}

find . -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} +

print_message "Copiando artefacto publicable a la rama build..."
cp -R "$STAGING"/* .

git add .
git commit -m "build: sanna-ui-rc v$NEW_VERSION"

print_message "Push a origin/build..."
git push origin HEAD:build --force

BUILD_COMMIT="$(git rev-parse HEAD)"

cd "$ORIGINAL_DIR" || exit 1

print_message "Creando y subiendo tag v$NEW_VERSION..."
git tag -a "v$NEW_VERSION" -m "Release sanna-ui-rc v$NEW_VERSION" "$BUILD_COMMIT"
git push origin "v$NEW_VERSION"

# --- 8. Limpieza worktree ---
print_message "Limpiando worktree y archivos temporales..."
git worktree remove -f "$BUILD_WORKTREE" 2>/dev/null || true

if [ -f "$STATE_DIR/temp-branch-name" ]; then
  TEMP_BRANCH="$(cat "$STATE_DIR/temp-branch-name")"
  git branch -D "$TEMP_BRANCH" 2>/dev/null || true
fi

rm -rf "$STATE_DIR"

FINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$FINAL_BRANCH" != "$CURRENT_BRANCH" ]; then
  print_warning "La rama cambió a $FINAL_BRANCH; volviendo a $CURRENT_BRANCH..."
  git checkout "$CURRENT_BRANCH"
fi

# --- 9. Commit del bump de versión en la rama de desarrollo ---
DEV_BRANCH="${VERSION_COMMIT_BRANCH:-$CURRENT_BRANCH}"

if [ "$DEV_BRANCH" != "$CURRENT_BRANCH" ]; then
  print_message "Cambiando a rama $DEV_BRANCH para commitear el bump de versión..."
  git checkout "$DEV_BRANCH"
fi

print_message "Commit del bump de versión en $DEV_BRANCH..."
git add package.json package-lock.json 2>/dev/null || git add package.json
git commit -m "chore: release sanna-ui-rc v$NEW_VERSION" || print_warning "Sin cambios que commitear (¿ya estaba commiteado?)."

git push origin "$DEV_BRANCH"

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || echo '')"

print_message "Proceso completado."
print_message "Nueva versión: $NEW_VERSION"
echo ""
print_message "Instalación desde Git (ejemplos; sustituye la URL por la de tu remoto):"
if [ -n "$ORIGIN_URL" ]; then
  echo "  Rama build:"
  echo "    \"sanna-ui-rc\": \"${ORIGIN_URL}#build\""
  echo ""
  echo "  Tag (recomendado para versiones fijas):"
  echo "    \"sanna-ui-rc\": \"${ORIGIN_URL}#v${NEW_VERSION}\""
else
  echo "  \"sanna-ui-rc\": \"git+https://github.com/USUARIO/REPO.git#build\""
  echo "  \"sanna-ui-rc\": \"git+https://github.com/USUARIO/REPO.git#v${NEW_VERSION}\""
fi
echo ""
