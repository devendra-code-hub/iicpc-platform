# Sandbox API Reference

Base URL: `http://localhost:4000`

## POST /submit
Upload contestant code.

**Form fields:**
- `code` (file): source code file (.cpp / .rs / .go)
- `language` (string): `cpp` | `rust` | `go`

**Response:**
```json
{ "submissionId": "uuid", "status": "received" }
```

## GET /submission/:id
Get submission status.

**Response:**
```json
{ "submissionId": "uuid", "status": "running", "port": "32768", "containerId": "abc123" }
```

## GET /submissions
List all submissions.

## DELETE /submission/:id
Stop and remove a submission container.

## GET /health
Health check.
```json
{ "status": "ok", "service": "sandbox-api", "total": 3 }
```
