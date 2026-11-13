"""Backend tests never touch the real catalogue: they get a throwaway one."""

import os
import tempfile

os.environ["CATALOG_STORE_DIR"] = tempfile.mkdtemp(prefix="catalog-test-")
os.environ.pop("CATALOG_ADMIN_KEY", None)
