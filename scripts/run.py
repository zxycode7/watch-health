#!/usr/bin/env python3
"""Stable absolute-path entry point for CLI and MCP clients."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from watchbridge.__main__ import main

if __name__ == "__main__":
    main()
