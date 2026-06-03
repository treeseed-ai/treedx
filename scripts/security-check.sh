#!/usr/bin/env bash
set -euo pipefail

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required security tool missing: $1" >&2
    exit 127
  }
}

require_tool cargo
require_tool npm
require_tool cargo-audit
require_tool syft
require_tool trivy
require_tool docker

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" cargo audit

(
  cd packages/ts-sdk
  audit_json="$(mktemp)"
  if ! npm audit --audit-level=high --json >"$audit_json"; then
    node - "$audit_json" ../../docs/security/accepted-vulnerabilities.md <<'NODE'
const fs = require('node:fs');

const [auditPath, acceptedPath] = process.argv.slice(2);
const audit = JSON.parse(fs.readFileSync(auditPath, 'utf8'));
const accepted = fs.existsSync(acceptedPath) ? fs.readFileSync(acceptedPath, 'utf8') : '';
const findings = [];

for (const [name, vulnerability] of Object.entries(audit.vulnerabilities || {})) {
  for (const via of vulnerability.via || []) {
    if (!via || typeof via === 'string') continue;
    if (!['high', 'critical'].includes(via.severity)) continue;
    const advisoryId = String(via.url || '').split('/').pop();
    findings.push({
      name,
      advisoryId,
      severity: via.severity,
      title: via.title || advisoryId,
    });
  }
}

const unaccepted = findings.filter((finding) => !finding.advisoryId || !accepted.includes(finding.advisoryId));
if (unaccepted.length > 0) {
  console.error('High or critical npm audit findings are not documented in docs/security/accepted-vulnerabilities.md:');
  for (const finding of unaccepted) {
    console.error(`- ${finding.name} ${finding.advisoryId || '(missing advisory id)'} ${finding.severity}: ${finding.title}`);
  }
  process.exit(1);
}

console.error(`Accepted ${findings.length} documented high/critical npm audit finding(s).`);
NODE
  fi
  rm -f "$audit_json"
)

mkdir -p target
syft dir:. -o spdx-json=target/treedb-sbom.spdx.json

docker build -t treedb-security-scan:local -f Dockerfile .
trivy image --exit-code 1 --severity HIGH,CRITICAL treedb-security-scan:local
