"""
Python implementation of a middle layer between the Open Notebook API and the
front‑end UI.

This module uses **FastAPI** to implement a simple proxy service.  It
forwards a subset of API calls (health checks and a hello endpoint) to
the underlying Open Notebook API and serves the front‑end static files
from the ``public`` directory.  In a production setting you could
extend this middle layer to handle authentication, caching,
aggregations and other business logic.

Usage::

    uvicorn middle_layer:app --host 0.0.0.0 --port 3000

Set the ``API_BASE_URL`` environment variable if your Open Notebook
API runs at a different address.  By default it points to
``http://localhost:5055/api``.
"""

import os
from pathlib import Path

import requests
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse, FileResponse


# Base URL of the downstream Open Notebook API.  The trailing /api is
# important – endpoints will be appended to this string directly.
API_BASE_URL = os.getenv("API_BASE_URL", "http://localhost:5055/api")

# Resolve the directory containing static files relative to this file
PUBLIC_DIR = Path(__file__).resolve().parent / "public"

app = FastAPI(title="Open Notebook Middle Layer", version="0.1.0")


def forward_get(endpoint: str, params: dict | None = None) -> JSONResponse:
    """Forward a GET request to the downstream API and return a JSON response.

    :param endpoint: Endpoint on the API, e.g. "/health" or "/hello".
    :param params: Dictionary of query parameters to include.
    :raises HTTPException: If the API is unreachable or returns non‑JSON.
    :returns: FastAPI JSONResponse mirroring the downstream response.
    """
    url = f"{API_BASE_URL.rstrip('/')}{endpoint}"
    try:
        resp = requests.get(url, params=params, timeout=10)
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail=f"Error contacting API: {exc}")
    try:
        data = resp.json()
    except Exception:
        # If the API didn't return JSON, bubble up the raw text
        raise HTTPException(status_code=502, detail="API returned non‑JSON response")
    return JSONResponse(status_code=resp.status_code, content=data)


@app.get("/health")
async def health_proxy() -> JSONResponse:
    """Proxy the /health endpoint to the downstream API."""
    return forward_get("/health")


@app.get("/hello")
async def hello_proxy(name: str = "world") -> JSONResponse:
    """Proxy the /hello endpoint to the downstream API."""
    return forward_get("/hello", params={"name": name})


@app.get("/", response_class=HTMLResponse)
async def index() -> HTMLResponse:
    """Serve the index.html file from the public directory."""
    index_path = PUBLIC_DIR / "index.html"
    if not index_path.exists():
        raise HTTPException(status_code=404, detail="UI not found")
    return HTMLResponse(index_path.read_text(encoding="utf-8"))


@app.get("/{asset_path:path}")
async def static_files(asset_path: str):
    """Serve other static assets from the public directory.

    Any path not matched by other routes will be treated as a static file
    relative to the ``public`` directory.  If the file does not exist
    a 404 error is returned.
    """
    file_path = PUBLIC_DIR / asset_path
    if not file_path.exists() or not file_path.is_file():
        raise HTTPException(status_code=404, detail="Asset not found")
    # Determine the MIME type based on file suffix
    suffix = file_path.suffix.lower()
    media_type = {
        ".html": "text/html",
        ".js": "text/javascript",
        ".css": "text/css",
        ".json": "application/json",
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
    }.get(suffix, "application/octet-stream")
    return FileResponse(str(file_path), media_type=media_type)