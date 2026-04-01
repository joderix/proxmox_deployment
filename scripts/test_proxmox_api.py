#!/usr/bin/env python3
"""
Phase 1: Test Proxmox API connectivity using the API token.
Verifies that the Proxmox API is accessible and the token has valid permissions.
"""

import os
import sys
import json
import urllib3
import requests

# Suppress InsecureRequestWarning for self-signed certs
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def get_env_or_exit(var_name: str) -> str:
    """Get environment variable or exit with error."""
    value = os.environ.get(var_name)
    if not value:
        print(f"[ERROR] Environment variable '{var_name}' is not set.")
        sys.exit(1)
    return value


def test_proxmox_api():
    """Test Proxmox API connectivity and token validity."""
    proxmox_url = get_env_or_exit("PROXMOX_URL")
    token_id = get_env_or_exit("PROXMOX_API_TOKEN_ID")
    token_secret = get_env_or_exit("PROXMOX_API_TOKEN_SECRET")

    print("=" * 60)
    print("  Phase 1: Proxmox API Connectivity Test")
    print("=" * 60)
    print(f"  API URL:    {proxmox_url}")
    print(f"  Token ID:   {token_id}")
    print(f"  Token:      {'*' * 20}...{token_secret[-4:]}")
    print("=" * 60)
    print()

    headers = {
        "Authorization": f"PVEAPIToken={token_id}={token_secret}"
    }

    # ── Test 1: Basic API connectivity ─────────────────────────────
    print("[TEST 1] Testing basic API connectivity...")
    try:
        response = requests.get(
            f"{proxmox_url}/version",
            headers=headers,
            verify=False,
            timeout=10
        )
        if response.status_code == 200:
            data = response.json().get("data", {})
            print(f"  [PASS] Proxmox VE {data.get('version', 'unknown')} "
                  f"(release: {data.get('release', 'unknown')})")
        else:
            print(f"  [FAIL] HTTP {response.status_code}: {response.text}")
            sys.exit(1)
    except requests.exceptions.ConnectionError as e:
        print(f"  [FAIL] Cannot connect to {proxmox_url}")
        print(f"         Error: {e}")
        sys.exit(1)
    except requests.exceptions.Timeout:
        print(f"  [FAIL] Connection timed out after 10s")
        sys.exit(1)

    # ── Test 2: Token permissions - list nodes ─────────────────────
    print("[TEST 2] Testing API token permissions (list nodes)...")
    try:
        response = requests.get(
            f"{proxmox_url}/nodes",
            headers=headers,
            verify=False,
            timeout=10
        )
        if response.status_code == 200:
            nodes = response.json().get("data", [])
            print(f"  [PASS] Found {len(nodes)} node(s):")
            for node in nodes:
                status = node.get("status", "unknown")
                name = node.get("node", "unknown")
                print(f"         - {name} (status: {status})")
        else:
            print(f"  [FAIL] HTTP {response.status_code}: {response.text}")
            sys.exit(1)
    except Exception as e:
        print(f"  [FAIL] Error: {e}")
        sys.exit(1)

    # ── Test 3: Storage access ─────────────────────────────────────
    node = os.environ.get("PROXMOX_NODE", "pve03")
    print(f"[TEST 3] Testing storage access on node '{node}'...")
    try:
        response = requests.get(
            f"{proxmox_url}/nodes/{node}/storage",
            headers=headers,
            verify=False,
            timeout=10
        )
        if response.status_code == 200:
            storages = response.json().get("data", [])
            print(f"  [PASS] Found {len(storages)} storage(s):")
            for s in storages:
                sname = s.get("storage", "unknown")
                stype = s.get("type", "unknown")
                content = s.get("content", "unknown")
                print(f"         - {sname} (type: {stype}, content: {content})")
        else:
            print(f"  [FAIL] HTTP {response.status_code}: {response.text}")
            sys.exit(1)
    except Exception as e:
        print(f"  [FAIL] Error: {e}")
        sys.exit(1)

    # ── Test 4: Check if ISO exists ────────────────────────────────
    iso_name = "Fedora-COSMIC-Atomic-ostree-x86_64-43-1.6.iso"
    print(f"[TEST 4] Checking for ISO '{iso_name}' on 'local' storage...")
    try:
        response = requests.get(
            f"{proxmox_url}/nodes/{node}/storage/local/content",
            headers=headers,
            verify=False,
            timeout=10
        )
        if response.status_code == 200:
            contents = response.json().get("data", [])
            iso_found = any(
                iso_name in item.get("volid", "")
                for item in contents
            )
            if iso_found:
                print(f"  [PASS] ISO '{iso_name}' found on local storage")
            else:
                print(f"  [WARN] ISO '{iso_name}' NOT found on local storage")
                print(f"         Please upload it before running Packer (Phase 2)")
                available_isos = [
                    item.get("volid", "") for item in contents
                    if item.get("content") == "iso"
                ]
                if available_isos:
                    print(f"         Available ISOs:")
                    for iso in available_isos:
                        print(f"           - {iso}")
        else:
            print(f"  [WARN] Could not list storage content: HTTP {response.status_code}")
    except Exception as e:
        print(f"  [WARN] Could not check ISO: {e}")

    print()
    print("=" * 60)
    print("  All critical tests PASSED! Proxmox API is accessible.")
    print("=" * 60)
    return 0


if __name__ == "__main__":
    sys.exit(test_proxmox_api())
