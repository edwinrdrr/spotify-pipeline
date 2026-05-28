"""HTTP entry point for the Cloud Function deployment.

Cloud Functions for Python looks for `main.py` in the source dir by default. This
file is a thin wrapper — all the real work lives in `snapshot.py:run_snapshot()`,
so CLI and Function paths share identical code.
"""
import traceback

import functions_framework

import snapshot


@functions_framework.http
def snapshot_http(request):
    """HTTP handler triggered by Cloud Scheduler. Body/method ignored."""
    try:
        snapshot.run_snapshot()
        return ("OK\n", 200)
    except Exception as e:
        traceback.print_exc()  # captured in Cloud Logging
        return (f"ERROR: {type(e).__name__}: {e}\n", 500)
