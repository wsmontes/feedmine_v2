#!/bin/sh
# Legacy catalog-v1 is incompatible with the current public manifest. Never install it.
echo "REFUSED: catalog-v1 release asset is not a verifiable public-catalogue bootstrap." >&2
echo "Run scripts/bootstrap_catalog.py with an explicitly SHA-256-pinned V1 compiler" >&2
echo "and catalog_identity.py; inspect staging and commit the paired Resources files." >&2
exit 2
