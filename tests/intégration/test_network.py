import os
from dotenv import load_dotenv


from pathlib import Path
load_dotenv()

USERNAME = os.environ["IOS_USERNAME"]
PASSWORD = os.environ["IOS_PASSWORD"]

import yaml
ROOT = Path(__file__).resolve().parents[2]
INVENTORY_FILE = ROOT / "ansible" / "inventory" / "hosts.yml"


def load_inventory():
    assert INVENTORY_FILE.is_file(), (
        f"Inventaire introuvable : {INVENTORY_FILE}"
    )

    with INVENTORY_FILE.open(encoding="utf-8") as file:
        return yaml.safe_load(file)


def test_inventory_yaml_is_valid():
    inventory = load_inventory()

    assert isinstance(inventory, dict)
    assert "all" in inventory


def test_ios_group_exists():
    inventory = load_inventory()

    children = inventory["all"].get("children", {})

    assert "ios" in children


def test_edge_and_core_groups_exist():
    inventory = load_inventory()

    ios = inventory["all"]["children"]["ios"]
    groups = ios.get("children", {})

    assert "edge" in groups
    assert "core" in groups


def test_ios_hosts_have_management_addresses():
    inventory = load_inventory()

    groups = inventory["all"]["children"]["ios"]["children"]

    for group_name in ("edge", "core"):
        hosts = groups[group_name].get("hosts", {})

        assert hosts, f"Aucun équipement dans le groupe {group_name}"

        for hostname, config in hosts.items():
            assert config.get("ansible_host"), (
                f"Adresse ansible_host absente pour {hostname}"
            )