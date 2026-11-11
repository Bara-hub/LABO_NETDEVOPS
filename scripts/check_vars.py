#!/usr/bin/env python3
"""Contrôles préventifs sur la source unique de vérité."""
import ipaddress
import sys
from pathlib import Path
import yaml

SSOT = Path("ansible/inventory/group_vars/all.yml")

def main() -> int:
    data = yaml.safe_load(SSOT.read_text(encoding="utf-8"))
    errors: list[str] = []
    networks: dict[str, ipaddress.IPv4Network] = {}

    ids = [v["id"] for v in data["vlans"]]
    for dup in sorted({i for i in ids if ids.count(i) > 1}):
        errors.append(f"VLAN {dup} déclaré plusieurs fois")

    for v in data["vlans"]:
        label = f"VLAN {v['id']} ({v['name']})"
        if not 1 <= int(v["id"]) <= 4094:
            errors.append(f"{label}: identifiant hors plage 1-4094")
        try:
            net = ipaddress.ip_network(v["subnet"], strict=True)
            gateway = ipaddress.ip_address(v["gateway"])
        except ValueError as exc:
            errors.append(f"{label}: adresse ou masque invalide ({exc})")
            continue
        if gateway not in net:
            errors.append(f"{label}: la passerelle {gateway} n'est pas dans {net}")
        networks[label] = net

    try:
        networks["transit"] = ipaddress.ip_network(data["transit"]["subnet"], strict=True)
    except ValueError as exc:
        errors.append(f"transit: adresse ou masque invalide ({exc})")

    labels = list(networks)
    for i, a in enumerate(labels):
        for b in labels[i + 1:]:
            if networks[a].overlaps(networks[b]):
                errors.append(f"chevauchement entre {a} ({networks[a]}) et {b} ({networks[b]})")

    sequences = [ace["sequence"] for ace in data["acl_users"]]
    if len(sequences) != len(set(sequences)):
        errors.append("ACL FILTER-USERS: numéros de séquence en double")

    for message in errors:
        print(f"ERREUR: {message}")
    print(f"{len(errors)} erreur(s) détectée(s)")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())