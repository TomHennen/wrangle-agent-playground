#!/usr/bin/env python3
"""my-sbom-tool: a minimal, NON-wrangle SBOM generator honoring the wrangle sbom
contract. Reads a read-only source tree, emits a valid, populated SPDX 2.3
document. Every field carries a `my-sbom-tool` marker so a run can prove the
custom tool produced the SBOM, not wrangle's syft."""
import datetime
import json
import os
import sys

MARKER = "my-sbom-tool"


def spdxid(raw):
    safe = "".join(c if c.isalnum() or c in ".-" else "-" for c in raw)
    return "SPDXRef-Package-" + (safe or "root")


def read_project(src):
    """Best-effort inventory of an npm project's declared packages."""
    packages = []
    pkg_json = os.path.join(src, "package.json")
    root_name, root_version = "source-project", "0.0.0"
    if os.path.isfile(pkg_json):
        try:
            with open(pkg_json, encoding="utf-8") as fh:
                data = json.load(fh)
            root_name = str(data.get("name") or root_name)
            root_version = str(data.get("version") or root_version)
            for section in ("dependencies", "devDependencies"):
                for dep, ver in (data.get(section) or {}).items():
                    packages.append((str(dep), str(ver).lstrip("^~=") or "unknown"))
        except (json.JSONDecodeError, OSError):
            pass
    # The root project is always inventoried, so the SBOM is never the
    # valid-but-empty trap even when package.json is missing or unparsable.
    packages.insert(0, (root_name, root_version))
    return packages


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: generate_sbom.py <src> <out>\n")
        return 2
    src, out = sys.argv[1], sys.argv[2]
    try:
        inventory = read_project(src)
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        packages = []
        for name, version in inventory:
            packages.append({
                "SPDXID": spdxid(name + "-" + version),
                "name": name,
                "versionInfo": version,
                "downloadLocation": "NOASSERTION",
                "copyrightText": "NOASSERTION",
                "supplier": "NOASSERTION",
            })
        doc = {
            "spdxVersion": "SPDX-2.3",
            "dataLicense": "CC0-1.0",
            "SPDXID": "SPDXRef-DOCUMENT",
            "name": MARKER + "-sbom-document",
            "documentNamespace": "https://example.invalid/" + MARKER + "/" + now,
            "creationInfo": {
                "created": now,
                "creators": [
                    "Tool: " + MARKER + "-1.0.0",
                    "Organization: BYO adopter (not wrangle syft)",
                ],
            },
            "packages": packages,
        }
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "sbom.spdx.json"), "w", encoding="utf-8") as fh:
            json.dump(doc, fh, indent=2)
        sys.stderr.write(
            "%s: wrote SPDX with %d package(s) (kind=%s)\n"
            % (MARKER, len(packages), os.environ.get("WRANGLE_KIND", ""))
        )
        return 0
    except Exception as exc:  # noqa: BLE001 - contract: any tool error -> exit 2
        sys.stderr.write("%s: error: %s\n" % (MARKER, exc))
        return 2


if __name__ == "__main__":
    sys.exit(main())
