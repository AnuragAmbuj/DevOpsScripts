#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:-lattice}"
ROOT_DIR="$PROJECT_NAME"

# -----------------------------
# Preflight (macOS-friendly)
# -----------------------------
need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: '$1' not found. Please install it first." >&2
    exit 1
  }
}
need bash
need cargo
command -v git >/dev/null 2>&1 || echo "Note: 'git' not found; skipping initial commit."

echo "Scaffolding monorepo at: $ROOT_DIR"

mk_lib_crate () {
  local path="$1"
  cargo new --lib "$path" --vcs none >/dev/null
  cat >> "$path/Cargo.toml" <<'EOF'

[package]
publish = false
EOF
  cat > "$path/README.md" <<EOF
# $(basename "$path")
Placeholder library crate. Implement via TDD.
EOF
  cat > "$path/src/lib.rs" <<'EOF'
//! Placeholder library crate. Implement via TDD.

#[cfg(test)]
mod tests {
    #[test] fn compiles() { assert_eq!(2 + 2, 4); }
}
EOF
}

mk_bin_crate () {
  local path="$1"
  local name; name="$(basename "$path")"
  cargo new --bin "$path" --vcs none >/dev/null
  cat >> "$path/Cargo.toml" <<'EOF'

[package]
publish = false
EOF
  cat > "$path/README.md" <<EOF
# $name
Binary entrypoint. Wire services here.
EOF
  cat > "$path/src/main.rs" <<EOF
//! Binary crate: $name
fn main() {
    println!("$name bootstrapped. Hook Pingora/HTTP server here.");
}
EOF
}

append_workspace_member () {
  printf '  "%s",\n' "$1" >> "$ROOT_DIR/Cargo.members"
}

mkdir -p "$ROOT_DIR"
pushd "$ROOT_DIR" >/dev/null

# Root workspace
cat > Cargo.toml <<'EOF'
[workspace]
resolver = "2"
members = [
# <MEMBERS>
]

[workspace.package]
edition = "2021"
license = "Apache-2.0"
authors = ["Your Team <dev@example.com>"]

[workspace.dependencies]
anyhow = "1"
thiserror = "1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["fmt", "env-filter"] }
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
# pingora = "0.6"
# wasmtime = "26"
# opentelemetry = "0.25"
EOF

cat > .gitignore <<'EOF'
/target
**/target
.DS_Store
node_modules
.env
.env.*
/console/.next
.idea
.vscode
Cargo.members
# keep placeholders
!.keep
!README.md
EOF

cat > README.md <<EOF
# $PROJECT_NAME

Programmable multi-tenant API Gateway + Zero-Trust Access Proxy.

- Data plane: \`/gateway\`
- Control plane: \`/control-plane\`
- Console UI: \`/console\`
- Contracts (source of truth): \`/contracts\`
- Tooling/CI/Docs included.

Start with TDD; see \`/docs/adr\`.
EOF

# ---------------- GATEWAY ----------------
GATEWAY_LIBS=(core proxy authn authz limits routing transforms observability snapshot plugin-sdk plugin-host tls errors commons)
for c in "${GATEWAY_LIBS[@]}"; do
  mk_lib_crate "gateway/crates/$c"
  append_workspace_member "gateway/crates/$c"
done

mk_bin_crate "gateway/bin/gatewayd"
append_workspace_member "gateway/bin/gatewayd"

mkdir -p gateway/tests/integration
: > gateway/tests/integration/.keep
echo "# Gateway tests" > gateway/tests/README.md

# ---------------- CONTROL PLANE ----------------
CP_LIBS=(domain storage events contracts)
for c in "${CP_LIBS[@]}"; do
  mk_lib_crate "control-plane/crates/$c"
  append_workspace_member "control-plane/crates/$c"
done

CP_SERVICES=(admin-api distributor idp secrets auditor)
for s in "${CP_SERVICES[@]}"; do
  mk_bin_crate "control-plane/services/$s"
  append_workspace_member "control-plane/services/$s"
done

mkdir -p control-plane/migrations control-plane/tests
: > control-plane/migrations/.keep
: > control-plane/tests/.keep
echo "# Control plane" > control-plane/README.md

# ---------------- CONSOLE ----------------
mkdir -p console/app console/components console/features console/lib console/e2e
cat > console/README.md <<'EOF'
# Console (UI)

Next.js + Tailwind + shadcn/ui recommended.
Generate client from /contracts/openapi.
EOF
: > console/app/.keep
: > console/components/.keep
: > console/features/.keep
: > console/lib/.keep
: > console/e2e/.keep

# ---------------- CONTRACTS ----------------
mkdir -p contracts/openapi/v1 contracts/proto/v1 contracts/schemas/snapshot/v1 contracts/schemas/policy/v1 contracts/plugin
cat > contracts/openapi/v1/admin-api.yaml <<'EOF'
openapi: 3.1.0
info: { title: Admin API, version: v1 }
paths: {}
components: {}
EOF
cat > contracts/proto/v1/gateway_watch.proto <<'EOF'
syntax = "proto3";
package contracts.v1;
message Snapshot { bytes blob = 1; string version = 2; }
message WatchRequest { string node_id = 1; string supported_schema = 2; }
service Distributor { rpc Watch(WatchRequest) returns (stream Snapshot); }
EOF
cat > contracts/schemas/snapshot/v1/schema.json <<'EOF'
{ "$schema":"https://json-schema.org/draft/2020-12/schema","title":"SnapshotV1","type":"object",
  "properties":{ "version":{"type":"string"},"tenants":{"type":"array"},"services":{"type":"array"} },
  "required":["version"] }
EOF
cat > contracts/schemas/policy/v1/README.md <<'EOF'
# Policy schema v1
Place Cedar model/schema and samples here.
EOF
cat > contracts/plugin/manifest.schema.json <<'EOF'
{ "$schema":"https://json-schema.org/draft/2020-12/schema","title":"PluginManifest","type":"object",
  "properties":{ "name":{"type":"string"},"version":{"type":"string"},"capabilities":{"type":"array","items":{"type":"string"}} },
  "required":["name","version"] }
EOF
echo "# Contracts" > contracts/README.md

# ---------------- PLUGINS ----------------
mkdir -p plugins/rust plugins/wasm
: > plugins/.keep
: > plugins/rust/.keep
: > plugins/wasm/.keep
echo "# Plugins playground" > plugins/README.md

# ---------------- TOOLING / DOCS / CI ----------------
mkdir -p tooling/helm tooling/k6 tooling/devcontainer tooling/scripts
: > tooling/helm/.keep
: > tooling/k6/.keep
: > tooling/devcontainer/.keep
: > tooling/scripts/.keep
echo "# Tooling" > tooling/README.md

mkdir -p docs/adr docs/runbooks docs/design
cat > docs/adr/0001-project-structure.md <<'EOF'
# ADR-0001: Project Structure
We use a monorepo with clear bounded contexts, versioned contracts, and independent deployables.
Contracts are the single source of truth; plugins sit behind a versioned SDK.
EOF
: > docs/runbooks/.keep
: > docs/design/.keep

mkdir -p .github/workflows
cat > .github/workflows/ci.yml <<'EOF'
name: CI
on: { push: { branches: ["main"] }, pull_request: {} }
jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Build
        run: cargo build --workspace --all-targets
      - name: Test
        run: cargo test --workspace --all-targets -- --nocapture
EOF

# Makefile (no GNU find)
cat > Makefile <<'EOF'
.PHONY: init build test fmt clippy tree
init: ; cargo --version
build: ; cargo build --workspace --all-targets
test: ; cargo test --workspace --all-targets -- --nocapture
fmt: ; cargo fmt --all
clippy: ; cargo clippy --workspace --all-targets -- -D warnings
# Portable tree using Python (works on macOS & Linux)
tree:
\tpython - <<'PY'
import os
max_depth = 4
for root, dirs, files in os.walk('.', topdown=True):
    depth = root.count(os.sep)
    if depth > max_depth: 
        dirs[:] = []
        continue
    print(root)
PY
EOF

# ---------------- Insert workspace members into Cargo.toml (BSD sed) ----------------
if [[ -f Cargo.members ]]; then
  # macOS/BSD sed requires a space before the backup suffix
  sed -i .bak '/# <MEMBERS>/r Cargo.members' Cargo.toml
  sed -i .bak '/# <MEMBERS>/d' Cargo.toml
  rm -f Cargo.members Cargo.toml.bak
fi

# Git init (optional)
if command -v git >/dev/null 2>&1; then
  git init >/dev/null 2>&1 || true
  git add . >/dev/null 2>&1 || true
  git commit -m "chore: scaffold monorepo with placeholders" >/dev/null 2>&1 || true
fi

popd >/dev/null
echo "Done ✅  Try: cd $ROOT_DIR && make tree && make build && make test"
