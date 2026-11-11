#!/usr/bin/env python3
import os
import requests

URL = os.environ["ZABBIX_URL"]
TOKEN = os.environ["ZABBIX_API_TOKEN"]
SNMP_COMMUNITY = os.environ["SNMP_COMMUNITY"]

DEVICES = [
    {"host": "R-EDGE", "ip": "10.10.0.9", "group": "Lab/Network", "template": "Cisco IOS by SNMP", "kind": "snmp"},
    {"host": "R-CORE", "ip": "10.10.0.2", "group": "Lab/Network", "template": "Cisco IOS by SNMP", "kind": "snmp"},
]

session = requests.Session()
session.headers.update({"Content-Type": "application/json-rpc", "Authorization": f"Bearer {TOKEN}"})

def api(method: str, params: dict):
    reply = session.post(URL, json={"jsonrpc": "2.0", "method": method, "params": params, "id": 1}, timeout=30)
    reply.raise_for_status()
    body = reply.json()
    if "error" in body:
        raise RuntimeError(f"{method}: {body['error'].get('data', body['error'])}")
    return body["result"]

def group_id(name: str) -> str:
    found = api("hostgroup.get", {"filter": {"name": [name]}})
    return found[0]["groupid"] if found else api("hostgroup.create", {"name": name})["groupids"][0]

def template_id(name: str) -> str:
    found = api("template.get", {"filter": {"host": [name]}})
    if not found:
        raise RuntimeError(f"modèle Zabbix introuvable : {name}")
    return found[0]["templateid"]

def interface(device: dict) -> dict:
    if device["kind"] == "snmp":
        return {"type": 2, "main": 1, "useip": 1, "ip": device["ip"], "dns": "", "port": "161",
                "details": {"version": 2, "bulk": 1, "community": "{$SNMP_COMMUNITY}"}}
    return {"type": 1, "main": 1, "useip": 1, "ip": device["ip"], "dns": "", "port": "10050"}

def ensure_host(device: dict) -> tuple[str, str]:
    query = {"filter": {"host": [device["host"]]}, "selectInterfaces": ["interfaceid"]}
    found = api("host.get", query)
    if not found:
        api("host.create", {
            "host": device["host"],
            "interfaces": [interface(device)],
            "groups": [{"groupid": group_id(device["group"])}],
            "templates": [{"templateid": template_id(device["template"])}],
            "macros": [{"macro": "{$SNMP_COMMUNITY}", "value": SNMP_COMMUNITY, "type": 1}],
        })
        print(f"hôte créé : {device['host']}")
        found = api("host.get", query)
    else:
        print(f"hôte déjà présent : {device['host']}")
    return found[0]["hostid"], found[0]["interfaces"][0]["interfaceid"]

def ensure_item(hostid: str, interfaceid: str, key: str, name: str, **extra) -> None:
    if api("item.get", {"hostids": hostid, "filter": {"key_": key}}):
        return
    api("item.create", {"hostid": hostid, "interfaceid": interfaceid, "key_": key, "name": name, **extra})
    print(f"  item créé : {key}")

def ensure_trigger(host: str, description: str, expression: str) -> None:
    if api("trigger.get", {"host": host, "filter": {"description": description}}):
        return
    api("trigger.create", {"description": description, "expression": expression, "priority": 4})
    print(f"  trigger créé : {description}")

def main() -> None:
    for device in DEVICES:
        hostid, ifaceid = ensure_host(device)
        if device["host"] == "R-CORE":
            ensure_item(hostid, ifaceid, "ospf.nbr.state", "État voisin OSPF R-EDGE",
                        type=20, snmp_oid="1.3.6.1.2.1.14.10.1.6.10.10.0.2.0", value_type=3, delay="10s")
            ensure_trigger("R-CORE", "OSPF : adjacence R-CORE/R-EDGE perdue",
                           "last(/R-CORE/ospf.nbr.state)<>8 or nodata(/R-CORE/ospf.nbr.state,30s)=1")
        if device["host"] == "SRV-RPA":
            ensure_item(hostid, ifaceid, "icmppingloss[,5]", "Perte de paquets vers SRV-RPA (%)",
                        type=3, value_type=0, delay="15s")
            ensure_trigger("SRV-RPA", "Perte de paquets > 5 % vers SRV-RPA",
                           "last(/SRV-RPA/icmppingloss[,5])>5")

if __name__ == "__main__":
    main()