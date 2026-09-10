#!/usr/bin/env python3
"""Verify CPU simulation placement/isolation and optionally pool autoscaling.

Uses only Python's standard library and kubectl. An explicit kubeconfig and
Terraform pool inventory prevent accidentally using the current context.
Creates and removes its own unique namespace; never modifies nodes.
"""
import argparse
import json
import subprocess
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--inventory", required=True, help="terraform output -json gpu_pools")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--scale-pool", help="Optional autoscaling pool with min=1, max>=2 and simulated 4-vCPU nodes")
    args = parser.parse_args()
    with open(args.inventory) as f:
        pools = json.load(f)
    if not pools or not all(p["simulated"] for p in pools.values()):
        parser.error("This test requires a nonempty CPU simulation inventory.")
    if args.scale_pool and args.scale_pool not in pools:
        parser.error("--scale-pool must be in the inventory")

    def kubectl(*command, body=None):
        result = subprocess.run(
            ["kubectl", "--kubeconfig", args.kubeconfig, *command],
            input=json.dumps(body) if body is not None else None,
            text=True, capture_output=True, check=True,
        )
        return result.stdout

    def get(*command):
        return json.loads(kubectl("get", *command, "-o", "json"))

    def wait_for(predicate, message):
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            if predicate():
                print("PASS:", message, flush=True)
                return
            time.sleep(5)
        raise RuntimeError("Timed out: " + message)

    def nodes_for(key):
        return get("nodes", "-l", "nebius.com/pool=" + key)["items"]

    for key in pools:
        wait_for(lambda key=key: bool(nodes_for(key)) and all(
            any(c["type"] == "Ready" and c["status"] == "True" for c in n["status"].get("conditions", []))
            for n in nodes_for(key)
        ), key + " nodes ready")
        for node in nodes_for(key):
            assert node["metadata"]["labels"].get("nebius.com/simulated") == "true", node["metadata"]["name"]
            assert not any(k.startswith("nvidia.com/") and float(v) > 0 for k, v in node["status"].get("allocatable", {}).items()), "Simulation advertises GPU resources"

    namespace = "pool-smoke-" + uuid.uuid4().hex[:10]
    kubectl("create", "namespace", namespace)
    try:
        def pod(name, key, tolerate=True, gpu=False, cpu="100m"):
            spec = {
                "restartPolicy": "Never",
                "nodeSelector": pools[key]["node_selector"],
                "containers": [{"name": "smoke", "image": "busybox:1.37.0", "command": ["sh", "-c", "sleep 3600"],
                                "resources": {"requests": {"cpu": cpu, "memory": "32Mi"}, "limits": {"memory": "64Mi"}}}],
            }
            if tolerate:
                spec["tolerations"] = pools[key]["tolerations"]
            if gpu:
                spec["containers"][0]["resources"]["limits"]["nvidia.com/gpu"] = "1"
            return {"apiVersion": "v1", "kind": "Pod", "metadata": {"name": name, "namespace": namespace}, "spec": spec}

        for key in pools:
            kubectl("create", "-f", "-", body=pod("place-" + key, key))

        def placed(key):
            p = get("pod", "place-" + key, "-n", namespace)
            if p["status"].get("phase") != "Running":
                return False
            n = get("node", p["spec"]["nodeName"])
            assert n["metadata"]["labels"]["nebius.com/pool"] == key
            return True

        for key in pools:
            wait_for(lambda key=key: placed(key), key + " workload on selected pool")

        key = next(iter(pools))
        if not any(t["effect"] in ("NoSchedule", "NoExecute") for t in pools[key]["tolerations"]):
            raise RuntimeError("Isolation test requires a hard taint on the first pool")
        kubectl("create", "-f", "-", body=pod("no-toleration", key, tolerate=False))
        kubectl("create", "-f", "-", body=pod("requires-real-gpu", key, gpu=True))

        def rejected(name, reason):
            p = get("pod", name, "-n", namespace)
            assert not p["spec"].get("nodeName"), name + " unexpectedly scheduled"
            events = get("events", "-n", namespace, "--field-selector", "involvedObject.name=" + name)["items"]
            return any(e.get("reason") == "FailedScheduling" and reason in e.get("message", "") for e in events)

        wait_for(lambda: rejected("no-toleration", "untolerated taint"), "missing toleration rejected by scheduler")
        wait_for(lambda: rejected("requires-real-gpu", "Insufficient nvidia.com/gpu"), "real GPU request stays unschedulable")

        if args.scale_pool:
            key = args.scale_pool
            baseline = {k: {n["metadata"]["name"] for n in nodes_for(k)} for k in pools}
            if len(baseline[key]) != 1:
                raise RuntimeError("Autoscaling test expects exactly one node initially in " + key)
            for i in range(2):
                kubectl("create", "-f", "-", body=pod("scale-" + str(i), key, cpu="2"))

            def scaled():
                pods = [get("pod", "scale-" + str(i), "-n", namespace) for i in range(2)]
                if not all(p["status"].get("phase") == "Running" for p in pods):
                    return False
                return len({p["spec"]["nodeName"] for p in pods}) == 2 and len(nodes_for(key)) >= 2

            wait_for(scaled, key + " scales out for pending CPU workloads")
            for other in pools.keys() - {key}:
                assert {n["metadata"]["name"] for n in nodes_for(other)} == baseline[other], other + " changed during unrelated pool scaling"
            print("PASS: other pools unchanged during scale-out", flush=True)
    except Exception:
        print(kubectl("get", "pods", "-n", namespace, "-o", "wide"))
        print(kubectl("get", "events", "-n", namespace, "--sort-by=.lastTimestamp"))
        raise
    finally:
        kubectl("delete", "namespace", namespace, "--wait=false")


if __name__ == "__main__":
    main()
