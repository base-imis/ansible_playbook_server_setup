#!/usr/bin/env python3
"""Create a GeoServer workspace from a fixed manifest and a database connection.

This script does not connect to or copy from a source GeoServer. The manifest
contains the approved datastore schemas, feature types, layer configuration,
and complete style bodies.
"""

import copy
import getpass
import json
import mimetypes
from pathlib import Path
from urllib.parse import quote

import requests


CONFIG = {
    # These values are collected interactively when the script starts.
    "GEOSERVER_URL": "",
    "USERNAME": "",
    "PASSWORD": "",
    "WORKSPACE": "",
    "NAMESPACE_URI": None,

    # Fixed source definition. No source GeoServer is used.
    "MANIFEST_PATH": str(Path(__file__).resolve().parent / "imis_base_source_configuration.json"),

    # Destination database used by every manifest datastore.
    "DATABASE_CONNECTION": {
        "host": "postgres14",
        "port": "5432",
        "database": "base-imis",
        "user": "appdb",
        "passwd": "",
        "dbtype": "postgis",
    },
    "DATABASE_CONNECTIONS": {},

    "DELETE_WORKSPACE_IF_EXISTS": False,
    "EXPOSE_PRIMARY_KEYS": True,
    "CREATE_STYLES": True,
    "LOCAL_ICONS_DIR": str(Path(__file__).resolve().parent / "icons"),
    "UPLOAD_LOCAL_ICONS": True,
    "SKIP_STYLE_NAMES": [],
}

DEFAULT_SRS = "EPSG:4326"


SESSION = None

FALLBACK_STYLE_BODIES = {
    "buildings_layer_functional_use": """/* Base IMIS v1.0.0 */

/* @title Residential */
[functional_use_id='1'] { fill: #000080; label: [bin]; }

/* @title Mixed (Residential, Commercial, Office uses) */
[functional_use_id='2'] { fill: #FF0000; label: [bin]; }

/* @title Educational */
[functional_use_id='3'] { fill: #6495ED; label: [bin]; }

/* @title Commercial */
[functional_use_id='5'] { fill: #964B00; label: [bin]; }

/* @title Industrial */
[functional_use_id='6'] { fill: #A020F0; label: [bin]; }

/* @title Institution */
[functional_use_id = '4'][NOT(functional_use_id is Null)],
[functional_use_id = '8'][NOT(functional_use_id is Null)],
[functional_use_id = '9'][NOT(functional_use_id is Null)],
[functional_use_id = '10'][NOT(functional_use_id is Null)],
[functional_use_id = '11'][NOT(functional_use_id is Null)],
[functional_use_id = '13'][NOT(functional_use_id is Null)] {
    fill: #FFFF00;
    label: [bin];
}

/* @title Others */
[functional_use_id = '7'][NOT(functional_use_id is Null)],
[functional_use_id = '12'][NOT(functional_use_id is Null)],
[functional_use_id = '14'][NOT(functional_use_id is Null)] {
    fill: #660033;
    label: [bin];
}

*:fill { stroke: gray; }
* {
    fill-opacity: 0.4;
    stroke: #000001;
    stroke-width: 0.01;
    stroke-opacity: 0.8;
    stroke-linejoin: bevel;
}
"""
}


def prompt_value(label, default="", secret=False, required=True):
    suffix = f" [{default}]" if default else ""
    prompt = f"{label}{suffix}: "
    value = getpass.getpass(prompt) if secret else input(prompt)
    value = value.strip()
    if not value:
        value = default
    if required and not value:
        raise ValueError(f"{label} is required")
    return value


def collect_runtime_configuration(manifest):
    """Ask for deployment-specific values without changing the manifest."""
    target = manifest.get("target", {})
    CONFIG["GEOSERVER_URL"] = prompt_value(
        "Target GeoServer URL", CONFIG["GEOSERVER_URL"]
    )
    CONFIG["USERNAME"] = prompt_value("GeoServer username", CONFIG["USERNAME"])
    CONFIG["PASSWORD"] = prompt_value(
        "GeoServer password", CONFIG["PASSWORD"], secret=True
    )
    CONFIG["WORKSPACE"] = prompt_value(
        "Workspace name", target.get("workspace") or CONFIG["WORKSPACE"]
    )
    CONFIG["NAMESPACE_URI"] = prompt_value(
        "Namespace URI (blank derives it from the GeoServer URL)",
        target.get("namespaceUri") or CONFIG["NAMESPACE_URI"] or "",
        required=False,
    ) or None

    # Always collect destination database credentials at import time. All
    # manifest datastores use the same destination connection; their schemas
    # remain datastore-specific. A GeoServer crypt1 value from an older
    # manifest is never treated as the current destination password.
    datastores = manifest.get("datastores", [])
    if datastores:
        first_source = (
            datastores[0].get("targetConnectionParameters")
            or datastores[0].get("connectionParameters")
            or {}
        )
        if isinstance(first_source.get("entry"), (list, dict)):
            entries = first_source.get("entry")
            entries = [entries] if isinstance(entries, dict) else entries
            first_source = {
                item.get("@key"): item.get("$", "")
                for item in entries
                if isinstance(item, dict)
            }

        print("Shared database connection (used by all stores)")
        shared_connection = {
            "host": prompt_value(
                "Database host",
                first_source.get("host", CONFIG["DATABASE_CONNECTION"]["host"]),
            ),
            "port": prompt_value(
                "Database port",
                first_source.get("port", CONFIG["DATABASE_CONNECTION"]["port"]),
            ),
            "database": prompt_value(
                "Database name",
                first_source.get("database", CONFIG["DATABASE_CONNECTION"]["database"]),
            ),
            "user": prompt_value(
                "Database user",
                first_source.get("user", CONFIG["DATABASE_CONNECTION"]["user"]),
            ),
            "passwd": prompt_value("Database password", "", secret=True, required=False),
            "dbtype": prompt_value(
                "Database type",
                first_source.get("dbtype", CONFIG["DATABASE_CONNECTION"]["dbtype"]),
            ),
        }

        for datastore in datastores:
            name = datastore.get("name", "store")
            source = (
                datastore.get("targetConnectionParameters")
                or datastore.get("connectionParameters")
                or {}
            )
            if isinstance(source.get("entry"), (list, dict)):
                entries = source.get("entry")
                entries = [entries] if isinstance(entries, dict) else entries
                source = {
                    item.get("@key"): item.get("$", "")
                    for item in entries
                    if isinstance(item, dict)
                }
            CONFIG["DATABASE_CONNECTIONS"][name] = {
                **shared_connection,
                "schema": source.get("schema", "public"),
            }


def initialize_session():
    global SESSION
    SESSION = requests.Session()
    SESSION.auth = (CONFIG["USERNAME"], CONFIG["PASSWORD"])
    SESSION.headers.update({"Accept": "application/json"})


def url(path):
    return CONFIG["GEOSERVER_URL"].rstrip("/") + "/" + path.lstrip("/")


def fail(response, label):
    if response.ok:
        return
    print(f"[{label}] {response.request.method} {response.url} -> {response.status_code}")
    if response.text:
        print(response.text[:4000])
    response.raise_for_status()


def get_json(path, allow_404=False):
    response = SESSION.get(url(path))
    if allow_404 and response.status_code == 404:
        return None
    fail(response, "GET")
    return response.json() if response.content else None


def post_json(path, payload, params=None):
    response = SESSION.post(
        url(path), json=payload, params=params,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    fail(response, "POST")
    return response


def put_json(path, payload, params=None):
    response = SESSION.put(
        url(path), json=payload, params=params,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    fail(response, "PUT")
    return response


def delete(path, params=None):
    response = SESSION.delete(url(path), params=params)
    if response.status_code not in (200, 202, 204, 404):
        fail(response, "DELETE")


def ensure_workspace():
    workspace = CONFIG["WORKSPACE"]
    if CONFIG["DELETE_WORKSPACE_IF_EXISTS"]:
        delete(f"rest/workspaces/{quote(workspace, safe='')}", {"recurse": "true"})

    namespace_uri = CONFIG["NAMESPACE_URI"] or f"{CONFIG['GEOSERVER_URL'].rstrip('/')}/{workspace}"
    namespace = get_json(f"rest/namespaces/{quote(workspace, safe='')}.json", allow_404=True)
    if not namespace:
        post_json("rest/namespaces", {"namespace": {"prefix": workspace, "uri": namespace_uri}})
    else:
        put_json(
            f"rest/namespaces/{quote(workspace, safe='')}.json",
            {"namespace": {"prefix": workspace, "uri": namespace_uri}},
        )

    existing = get_json(f"rest/workspaces/{quote(workspace, safe='')}.json", allow_404=True)
    if not existing:
        post_json("rest/workspaces", {"workspace": {"name": workspace}})


def connection_parameters(existing, override=None):
    params = copy.deepcopy(existing or {})
    entries = params.get("entry", [])
    if isinstance(entries, dict):
        entries = [entries]
    values = {entry.get("@key"): entry for entry in entries if isinstance(entry, dict)}

    overrides = dict(override or CONFIG["DATABASE_CONNECTION"])
    if CONFIG["EXPOSE_PRIMARY_KEYS"]:
        overrides["Expose primary keys"] = "true"

    for key, value in overrides.items():
        if key in values:
            values[key]["$"] = str(value)
        else:
            entries.append({"@key": key, "$": str(value)})
    params["entry"] = entries
    return params


def create_datastore(datastore):
    workspace = CONFIG["WORKSPACE"]
    name = datastore["name"]
    body = {
        "name": name,
        "type": datastore.get("type", "PostGIS"),
        "enabled": datastore.get("enabled", True),
        "workspace": {"name": workspace},
        "connectionParameters": connection_parameters(
            datastore.get("connectionParameters"),
            CONFIG["DATABASE_CONNECTIONS"].get(name)
            or datastore.get("targetConnectionParameters"),
        ),
    }
    existing = get_json(
        f"rest/workspaces/{quote(workspace, safe='')}/datastores/{quote(name, safe='')}.json",
        allow_404=True,
    )
    if existing:
        put_json(
            f"rest/workspaces/{quote(workspace, safe='')}/datastores/{quote(name, safe='')}.json",
            {"dataStore": body},
        )
        print(f"Updated datastore: {name}")
        return
    post_json(f"rest/workspaces/{quote(workspace, safe='')}/datastores", {"dataStore": body})
    print(f"Created datastore: {name}")


def create_feature_type(datastore_name, feature_wrapper):
    workspace = CONFIG["WORKSPACE"]
    body = copy.deepcopy(feature_wrapper.get("featureType", feature_wrapper))
    for key in ("id", "href", "store", "namespace", "nativeBoundingBox", "latLonBoundingBox", "metadataLinks", "dataLinks", "prefixedName"):
        body.pop(key, None)
    body["name"] = body.get("name") or body.get("nativeName")
    body["nativeName"] = body.get("nativeName") or body["name"]
    body["srs"] = body.get("srs") or DEFAULT_SRS

    name = body["name"]
    endpoint = (
        f"rest/workspaces/{quote(workspace, safe='')}/datastores/"
        f"{quote(datastore_name, safe='')}/featuretypes/{quote(name, safe='')}.json"
    )
    if get_json(endpoint, allow_404=True):
        print(f"Feature type exists: {datastore_name}:{name}")
        return
    featuretypes_path = (
        f"rest/workspaces/{quote(workspace, safe='')}/datastores/"
        f"{quote(datastore_name, safe='')}/featuretypes"
    )
    post_json(featuretypes_path, {"featureType": body})
    put_json(
        endpoint,
        {"featureType": body},
        params={"recalculate": "nativebbox,latlonbbox"},
    )
    print(f"Created layer: {workspace}:{name}")


def normalize_style_ref(style):
    if not isinstance(style, dict):
        return style
    result = {key: value for key, value in style.items() if key != "href"}
    result["workspace"] = {"name": CONFIG["WORKSPACE"]}
    return result


def apply_layer_configuration(layer_record):
    layer = copy.deepcopy(layer_record.get("layer", {}).get("layer", layer_record.get("layer", {})))
    if not layer:
        return
    full_name = layer.get("name", "")
    name = full_name.split(":", 1)[-1]
    if not name:
        return
    layer.pop("href", None)
    layer["name"] = CONFIG["WORKSPACE"] + ":" + name
    if isinstance(layer.get("resource"), dict):
        layer["resource"].pop("href", None)
        layer["resource"].pop("store", None)
    if isinstance(layer.get("defaultStyle"), dict):
        layer["defaultStyle"] = normalize_style_ref(layer["defaultStyle"])
    if isinstance(layer.get("styles"), dict):
        styles = layer["styles"].get("style", [])
        styles = [styles] if isinstance(styles, dict) else styles
        layer["styles"] = {"style": [normalize_style_ref(style) for style in styles]}
    put_json(
        f"rest/layers/{quote(CONFIG['WORKSPACE'] + ':' + name, safe='')}.json",
        {"layer": layer},
    )
    print(f"Applied layer configuration: {name}")


def create_styles(styles):
    if not CONFIG["CREATE_STYLES"]:
        return
    workspace = CONFIG["WORKSPACE"]
    skipped = set(CONFIG["SKIP_STYLE_NAMES"])
    for item in styles:
        listing = item.get("listing", {})
        name = item.get("name") or listing.get("name")
        if not name or name in skipped:
            continue
        if get_json(f"rest/workspaces/{quote(workspace, safe='')}/styles/{quote(name, safe='')}.json", allow_404=True):
            print(f"Style exists: {name}")
            continue
        body = item.get("body") or item.get("css", "")
        if not body:
            print(f"Skipped empty style: {name}")
            continue
        style_format = item.get("format") or item.get("bodyFormat")
        content_type = "application/vnd.geoserver.geocss+css" if style_format == "CSS" else "application/vnd.ogc.sld+xml"
        response = SESSION.post(
            url(f"rest/workspaces/{quote(workspace, safe='')}/styles"),
            params={"name": name}, data=body.encode("utf-8"),
            headers={"Content-Type": content_type},
        )
        fail(response, "STYLE POST")
        print(f"Created style: {name}")


def create_fallback_styles(manifest_styles):
    """Create known project styles when the source did not provide them."""
    workspace = CONFIG["WORKSPACE"]
    manifest_names = {
        item.get("listing", {}).get("name")
        for item in manifest_styles
        if isinstance(item, dict) and item.get("body", "").strip()
    }
    for name, body in FALLBACK_STYLE_BODIES.items():
        if name in manifest_names:
            continue
        if get_json(
            f"rest/workspaces/{quote(workspace, safe='')}/styles/{quote(name, safe='')}.json",
            allow_404=True,
        ):
            continue
        response = SESSION.post(
            url(f"rest/workspaces/{quote(workspace, safe='')}/styles"),
            params={"name": name},
            data=body.encode("utf-8"),
            headers={"Content-Type": "application/vnd.geoserver.geocss+css"},
        )
        fail(response, "FALLBACK STYLE POST")
        print(f"Created fallback style: {name}")


def upload_icons():
    if not CONFIG["UPLOAD_LOCAL_ICONS"]:
        return
    icon_dir = Path(CONFIG["LOCAL_ICONS_DIR"])
    if not icon_dir.is_dir():
        print(f"Icons directory not found: {icon_dir}")
        return
    for path in sorted(p for p in icon_dir.rglob("*") if p.is_file()):
        relative = path.relative_to(icon_dir).as_posix()
        resource = f"workspaces/{CONFIG['WORKSPACE']}/styles/icons/{relative}"
        with path.open("rb") as handle:
            response = SESSION.put(
                url(f"rest/resource/{resource}"), data=handle,
                headers={"Content-Type": mimetypes.guess_type(path.name)[0] or "application/octet-stream"},
            )
        fail(response, "ICON PUT")
        print(f"Uploaded icon: {relative}")


def main():
    manifest_path = Path(prompt_value("Manifest JSON file", CONFIG["MANIFEST_PATH"]))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    collect_runtime_configuration(manifest)
    initialize_session()
    ensure_workspace()
    for datastore in manifest.get("datastores", []):
        create_datastore(datastore)
        for feature_type in datastore.get("featureTypes", []):
            create_feature_type(datastore["name"], feature_type)
    upload_icons()
    create_styles(manifest.get("styles", []))
    create_fallback_styles(manifest.get("styles", []))
    for layer in manifest.get("layers", []):
        apply_layer_configuration(layer)
    print("Completed manifest-based workspace creation.")


if __name__ == "__main__":
    main()
