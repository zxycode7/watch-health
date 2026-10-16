import re
import unittest
from pathlib import Path
from watchbridge.store import TYPES

class CatalogTests(unittest.TestCase):
    def test_native_and_backend_accept_exactly_the_same_metric_units(self):
        source=(Path(__file__).resolve().parents[1]/"ios/WatchBridge/Models.swift").read_text()
        unit_switch=source.split("var unit: String",1)[1].split("var group:",1)[0]
        native=dict(re.findall(r'case \.(\w+): "([^\"]+)"',unit_switch))
        self.assertEqual(native,{key:value[1] for key,value in TYPES.items()})
        self.assertEqual(len(native),28)
