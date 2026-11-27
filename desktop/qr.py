"""Local QR encoding for the pairing page.

The token stays on this computer. No third-party QR APIs.
Vendored encoder: desktop/qrcodegen.py (Nayuki, MIT).
"""

from __future__ import annotations

from qrcodegen import QrCode


def matrix(text: str) -> list[list[bool]]:
    """Square grid, True = dark module."""
    qr = QrCode.encode_text(text, QrCode.Ecc.MEDIUM)
    n = qr.get_size()
    return [[qr.get_module(x, y) for x in range(n)] for y in range(n)]


def svg(text: str, border: int = 4) -> str:
    """Standalone SVG for the pairing page (white quiet zone, black modules)."""
    qr = QrCode.encode_text(text, QrCode.Ecc.MEDIUM)
    n = qr.get_size()
    dim = n + border * 2
    d = []
    for y in range(n):
        for x in range(n):
            if qr.get_module(x, y):
                d.append(f"M{x + border},{y + border}h1v1h-1z")
    path = "".join(d)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {dim} {dim}" '
        f'shape-rendering="crispEdges" width="280" height="280">'
        f'<rect width="{dim}" height="{dim}" fill="#ffffff"/>'
        f'<path fill="#111111" d="{path}"/>'
        f"</svg>"
    )
