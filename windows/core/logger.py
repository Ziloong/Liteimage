"""Debug 日志"""

import os
import logging
from datetime import datetime

LOG_DIR = os.path.join(os.path.expanduser("~"), "AppData", "Local", "LiteImage", "logs")
os.makedirs(LOG_DIR, exist_ok=True)

logger = logging.getLogger("LiteImage")
logger.setLevel(logging.DEBUG)

# 文件 handler
log_file = os.path.join(LOG_DIR, f"debug-{datetime.now():%Y-%m-%d}.log")
fh = logging.FileHandler(log_file, encoding="utf-8")
fh.setLevel(logging.DEBUG)
fh.setFormatter(logging.Formatter("%(asctime)s %(message)s", datefmt="%Y-%m-%d %H:%M:%S"))
logger.addHandler(fh)


def enable(flag: bool):
    """开关调试日志"""
    fh.setLevel(logging.DEBUG if flag else logging.CRITICAL + 1)


def get_log_path():
    return log_file


def get_log_dir():
    return LOG_DIR
