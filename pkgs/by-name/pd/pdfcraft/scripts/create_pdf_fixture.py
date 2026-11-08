"""Validate generated artifacts in an isolated build or VM fixture."""

from pathlib import Path

objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] /Resources << >> >>",
]
data = b"%PDF-1.4\n"
offsets = [0]
for index, content in enumerate(objects, 1):
    offsets.append(len(data))
    data += f"{index} 0 obj\n".encode() + content + b"\nendobj\n"
xref = len(data)
data += b"xref\n0 4\n0000000000 65535 f \n"
data += b"".join(f"{offset:010d} 00000 n \n".encode() for offset in offsets[1:])
data += f"trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
Path("input.pdf").write_bytes(data)
