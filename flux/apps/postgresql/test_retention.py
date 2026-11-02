"""Run with python3 test_retention.py; requires the repository's yq CLI."""
import copy
import json
from pathlib import Path
import subprocess
import unittest

script = subprocess.check_output(
    ["yq", "-r", '.data["retention.py"]', str(Path(__file__).with_name("configmap.yaml"))],
    text=True,
)
namespace = {"__name__": "retention_test"}
exec(compile(script, "retention.py", "exec"), namespace)
expired = namespace["expired"]


def backup(index, phase="completed"):
    return {
        "metadata": {"name": f"backup-{index}", "labels": {
            "cnpg.io/scheduled-backup": "postgres-longhorn-daily"}},
        "spec": {"cluster": {"name": "postgres-longhorn"}, "method": "volumeSnapshot"},
        "status": {"phase": phase, "stoppedAt": f"2026-11-{index:02}T01:00:00Z"},
    }


class RetentionTest(unittest.TestCase):
    def test_keeps_seven_and_removes_oldest_regardless_of_input_order(self):
        items = [backup(i) for i in (8, 1, 9, 3, 2, 4, 7, 5, 6)]
        self.assertEqual([b["metadata"]["name"] for b in expired(items)], ["backup-2", "backup-1"])

    def test_keeps_everything_until_seven_successes(self):
        self.assertEqual(expired([backup(i) for i in range(1, 8)]), [])
        self.assertEqual(expired([]), [])

    def test_excludes_failed_running_manual_and_other_clusters(self):
        items = [backup(i) for i in range(1, 8)]
        items += [backup(8, "failed"), backup(9, "running")]
        manual = backup(10)
        manual["metadata"]["labels"] = {}
        other = backup(11)
        other["spec"]["cluster"]["name"] = "other"
        different_method = copy.deepcopy(backup(12))
        different_method["spec"]["method"] = "plugin"
        self.assertEqual(expired(items + [manual, other, different_method]), [])


if __name__ == "__main__":
    unittest.main()
