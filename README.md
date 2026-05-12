# trivy-in-action

A minimal end-to-end demo of [**Trivy**](https://trivy.dev/) running inside a
GitHub Actions pipeline. A tiny Python service is built into a container, and
the image is **only published to GHCR if Trivy is happy with both the
Dockerfile and the resulting image**. If either scan finds a HIGH or CRITICAL
issue, the pipeline fails and nothing is pushed.

---

## What's in this repo

| Path | Purpose |
| --- | --- |
| [`app.py`](./app.py) | A stdlib-only HTTP server with `/` and `/health`. |
| [`Dockerfile`](./Dockerfile) | `python:3.12-slim`, non-root user, healthcheck, no `:latest` tag &mdash; written to pass Trivy's config policies. |
| [`.dockerignore`](./.dockerignore) | Keeps the build context small. |
| [`.github/workflows/build-scan-push.yml`](./.github/workflows/build-scan-push.yml) | The CI pipeline described below. |

---

## The pipeline

`.github/workflows/build-scan-push.yml` runs on every push to `main`, on PRs
targeting `main`, and on manual `workflow_dispatch`. It does four things, in
order, and the job fails immediately at the first red step:

1. **Trivy config scan** &mdash; `scan-type: config` over the repo. Flags
   Dockerfile misconfigurations such as running as root, missing `USER`,
   `ADD` of remote URLs, or `FROM` with `:latest`. Gate:
   `severity: HIGH,CRITICAL`, `exit-code: 1`.
2. **Build (load locally, do not push)** &mdash; `docker/build-push-action`
   with `load: true` builds the image into the runner's local Docker daemon as
   `trivy-demo:<sha>`. Nothing leaves the runner yet.
3. **Trivy image scan** &mdash; scans the just-built local image for
   `os,library` CVEs (`ignore-unfixed: true`, `severity: HIGH,CRITICAL`,
   `exit-code: 1`). A second Trivy invocation produces SARIF, which is uploaded
   to GitHub's Security tab via `github/codeql-action/upload-sarif` and also
   attached to the workflow run as a downloadable artifact.
4. **Publish to GHCR** &mdash; only on non-PR events, and only if all of the
   above passed. Logs in with the auto-provided `GITHUB_TOKEN`, computes tags
   with `docker/metadata-action` (branch, full SHA, plus `latest` on the
   default branch), and pushes. The push reuses the GHA build cache, so it's
   essentially a metadata-only operation.

PRs run steps 1&ndash;3 only and never publish, so external contributors get
full scan feedback without push access.

### Permissions used by the workflow

```yaml
permissions:
  contents: read
  packages: write          # push to GHCR
  security-events: write   # upload SARIF to the Security tab
```

No additional secrets are required &mdash; `GITHUB_TOKEN` is enough to push to
`ghcr.io/<owner>/<repo>`.

### Where to find the SARIF report

When the **local image build** step succeeds, Trivy writes `trivy-image.sarif`
and the workflow does two things with it:

1. **GitHub Security &rarr; Code scanning** &mdash; the `upload-sarif` step sends
   the file to GitHub. Open your repository, then **Security**, then **Code
   scanning** (wording can vary slightly by plan). Findings appear there after
   processing (usually within a minute). If **Code scanning** is not available
   for your org or plan, the upload step may still succeed but the UI will not
   show a dedicated code-scanning view.
2. **Actions run artifacts** &mdash; each successful SARIF generation also
   uploads an artifact named **`trivy-image-sarif`**. Open the workflow run,
   scroll to **Artifacts** at the bottom, and download the ZIP (it contains
   `trivy-image.sarif`).

If an earlier step fails **before** the image is built (for example, the
config scan fails), no SARIF file is produced for that run, because there is no
image to scan.

---

## Running the app locally

```bash
docker build -t trivy-demo:local .
docker run --rm -p 8000:8000 trivy-demo:local
curl http://localhost:8000/health   # -> ok
```

Or without Docker:

```bash
python app.py
```

---

## Running Trivy locally (same gates as CI)

Install Trivy: <https://aquasecurity.github.io/trivy/latest/getting-started/installation/>.

```bash
# 1. Dockerfile / IaC misconfiguration scan
trivy config --severity HIGH,CRITICAL --exit-code 1 .

# 2. Image vulnerability scan (build first)
docker build -t trivy-demo:local .
trivy image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --vuln-type os,library \
  --exit-code 1 \
  trivy-demo:local
```

---

## Watching Trivy actually fail the pipeline

The repo as-shipped is intentionally clean &mdash; CI should be green. To see
Trivy block a build, try one of these:

- **Config failure**: in `Dockerfile`, remove the `USER appuser` line, or
  change `FROM python:3.12-slim` to `FROM python:latest`. Step&nbsp;1 will fail.
- **Vulnerability failure**: in `Dockerfile`, change the base to an older image
  such as `FROM python:3.9-slim-bullseye`, and in the workflow remove
  `ignore-unfixed: true`. Step&nbsp;3 will surface fixable HIGH/CRITICAL OS CVEs
  and exit non-zero before the login/push steps ever run.

In both cases, no image is published &mdash; that's the whole point.

---

## Using the published image

Once CI is green on `main`, the image is available at:

```
ghcr.io/<owner>/<repo>:latest
ghcr.io/<owner>/<repo>:main
ghcr.io/<owner>/<repo>:sha-<full-commit-sha>
```

Pull and run:

```bash
docker run --rm -p 8000:8000 ghcr.io/<owner>/<repo>:latest
```

Packages published to GHCR start out private &mdash; flip them to public from
the package settings if you want anonymous pulls.

---

## First-time setup

1. Push this repo to GitHub.
2. **Settings &rarr; Actions &rarr; General &rarr; Workflow permissions**:
   confirm `GITHUB_TOKEN` has the permissions declared in the workflow
   (`packages: write`, `security-events: write`). For repos you own personally
   this is on by default; some org policies restrict it.
3. Push to `main` (or run the workflow manually). The first run will populate
   the GHA build cache; subsequent runs are noticeably faster.
