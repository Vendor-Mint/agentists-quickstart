# K8s Cloud Workspace

Cloud-native DevContainer that runs inside a Kubernetes pod. Each developer gets an isolated namespace provisioned by `k8s-cloud-manager`, attaches to it with a kubeconfig, and lands in a fully wired dev environment: Claude Code CLI, MCP servers (Playwright, GitHub, Context7, Filesystem, Atlassian), `gcloud`, `kubectl`, `helm`, Docker-in-Docker, Node.js, Python, .NET, Playwright with Chromium, and `cloudflared` for exposing local apps to the public internet via `*.<dev_name>.dev.vendormint.ai`.

---

## How you get here

You do not clone this repo locally. The workflow is:

1. **Admin** provisions your environment with `k8s-cloud-manager` and sends you a `kubeconfig-<dev_name>.yaml` file.
2. You drop it in `~/.kube/config` and use **VS Code Dev Containers** (right-click your pod under the Kubernetes sidebar → *Attach Visual Studio Code*) or **DevPod** with a Kubernetes provider pointed at that kubeconfig.
3. On first attach, `.devcontainer/on-create.sh` runs and bootstraps everything that can be automated. The steps in this README are what it cannot automate — they need you to authenticate interactively or to make per-developer decisions.

Throughout this document, `<dev_name>` is the name admin used when provisioning your environment (e.g. the one passed to `./provision-dev.sh <dev_name>`). It shows up in your namespace (`dev-<dev_name>`), your tunnel hostnames, and the kubeconfig filename.

---

## Post-create checklist

Run these once after the container is up and running.

### 1. Authenticate GitHub CLI (SSH)

Both day-to-day `git` work and the **GitHub MCP server** (installed as the `gh-mcp` extension) depend on `gh` being logged in. Inside the container:

```bash
gh auth login
```

Answer the prompts:

- **What account do you want to log into?** → `GitHub.com`
- **What is your preferred protocol for Git operations?** → `SSH`
- **Generate a new SSH key to add to your GitHub account?** → `Yes`
- **Enter a passphrase** → leave empty (or choose one — it will prompt on each push)
- **Title for your SSH key** → default (`GitHub CLI`) is fine
- **How would you like to authenticate GitHub CLI?** → `Login with a web browser`

Copy the one-time code shown in the terminal, open the URL on your local machine, paste the code, approve. `gh` uploads the generated public key to your GitHub account and saves the private key at `~/.ssh/id_ed25519` inside the container. From this point, `git clone git@github.com:...` and all MCP GitHub tools work.

Verify:

```bash
gh auth status
ssh -T git@github.com
```

### 2. Configure your Git identity

`gh auth login` logs you into GitHub but does **not** set the commit author. Do it yourself once, with the same email you use on GitHub so commits are attributed to your profile:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@vendormint.com"
```

Verify:

```bash
git config --global --get user.name
git config --global --get user.email
```

### 3. Configure `gcloud` and the Cloud SQL Auth Proxy

The container ships with `gcloud` and `cloud-sql-proxy` pre-installed. You still need to log in and point them at the right project and DB instance.

#### 3.1 Log in and select the project

```bash
gcloud auth login
```

This prints a URL, you open it on your local machine, approve, and paste the verification code back into the terminal.

Then set the active project (ask admin for the exact project ID if you do not know it):

```bash
gcloud config set project <gcp-project-id>
```

Verify:

```bash
gcloud config list
gcloud auth list
```

#### 3.2 Set up Application Default Credentials (ADC)

ADC is what Google client libraries (Python, Node, Go SDKs, `cloud-sql-proxy`, Cloud Code extension, etc.) use to authenticate transparently. Run:

```bash
gcloud auth application-default login
```

Same browser flow. The resulting credentials are stored at `~/.config/gcloud/application_default_credentials.json` and are picked up automatically by any tool that honours ADC.

#### 3.3 Connect to Cloud SQL via `cloud-sql-proxy`

Ask admin for your database's **instance connection name** (format: `<project>:<region>:<instance>`). Then in a dedicated terminal:

```bash
cloud-sql-proxy <project>:<region>:<instance> --port 5432
```

Leave it running. Your local apps can now connect to the database at `localhost:5432` as if it were local, with IAM authentication handled by the proxy. Adjust `--port` if 5432 is already in use or if your stack expects a different port.

Tip: run it inside `tmux` alongside `cloudflared tunnel run` so both background processes survive your terminal being closed.

### 4. Authenticate the Atlassian (Jira / Confluence) MCP

Atlassian uses OAuth, not API keys, and the flow is driven by **Claude itself** — not by a CLI command. Open a Claude Code session in the container and send a prompt such as:

```text
Authenticate the Jira MCP and verify it works — show my Jira profile information.
```

Claude will:

1. Attempt a Jira tool call.
2. Print an OAuth URL in the terminal.
3. You open the URL on your **local** machine, approve the app for your Vendormint workspace, and return.
4. Claude retries the tool call and shows the list of projects, confirming the MCP is wired up.

Sessions persist on disk, so you only do this once per container volume. If Claude later says the session expired, just re-run the same prompt.

### 5. Configure and run your Cloudflare tunnel

`on-create.sh` has already pulled your tunnel token from the namespace secret and written:

- `~/.cloudflared/<tunnel-id>.json` — the credentials file (do not edit).
- `~/.cloudflared/config.yml` — routing config, generated from `.devcontainer/cloudflared/config.yml.template`. **This is the file you edit.**

#### Add ingress rules for your apps

Open `~/.cloudflared/config.yml`. You will see something like:

```yaml
tunnel: <your-tunnel-id>
credentials-file: /home/vscode/.cloudflared/<your-tunnel-id>.json

ingress:
  #- hostname: app1.<dev_name>.dev.vendormint.ai
  #  service: http://localhost:4321
  #- hostname: api.<dev_name>.dev.vendormint.ai
  #  service: http://localhost:3000
  - service: http_status:404
```

Uncomment or add one entry per app you want to expose. Rules:

- **Hostname pattern**: `<app>.<dev_name>.dev.vendormint.ai`. Wildcard DNS covers every subdomain, so new hostnames require no admin action.
- **Service**: the local URL where your app is listening inside the container, usually `http://localhost:<port>`.
- The final `- service: http_status:404` catch-all must stay as the last entry — cloudflared rejects the config without it.

Example for a developer running a frontend on 4321, an API on 3000, and a websocket server on 8080:

```yaml
tunnel: <your-tunnel-id>
credentials-file: /home/vscode/.cloudflared/<your-tunnel-id>.json

ingress:
  - hostname: web.<dev_name>.dev.vendormint.ai
    service: http://localhost:4321
  - hostname: api.<dev_name>.dev.vendormint.ai
    service: http://localhost:3000
  - hostname: ws.<dev_name>.dev.vendormint.ai
    service: http://localhost:8080
  - service: http_status:404
```

#### Run the tunnel

From any terminal in the container:

```bash
cloudflared tunnel run
```

The process stays attached and streams connection logs. Keep it running while you develop; `Ctrl+C` to stop. If you edit `config.yml`, restart the tunnel so it picks up the new rules.

Tip: run it inside `tmux` or a second VS Code terminal so it survives tab closures without losing output.

Your apps are now reachable at `https://<app>.<dev_name>.dev.vendormint.ai`, gated by Cloudflare Access — you log in with your `@vendormint.com` email.

---

## Daily workflow

Use `tmux` (or multiple VS Code terminals) to keep the long-running processes side by side:

```bash
# Terminal 1 — your app
npm run dev

# Terminal 2 — Cloud SQL Auth Proxy
cloud-sql-proxy <project>:<region>:<instance> --port 5432

# Terminal 3 — Cloudflare tunnel
cloudflared tunnel run
```

Open `https://<app>.<dev_name>.dev.vendormint.ai` in your browser. Ship. Repeat.

---

## Troubleshooting

**`gh` commands fail with "not authenticated":** re-run `gh auth login` and pick SSH again.

**`git push` asks for a password or fails with "Permission denied (publickey)":** the SSH key wasn't uploaded. Run `gh auth status` to confirm; if the key is missing, re-run `gh auth login` and answer *Yes* to *Generate a new SSH key*.

**Commits show up as `vscode <vscode@...>` on GitHub:** you skipped the git identity step. Set `user.name` and `user.email`, then amend the offending commit (`git commit --amend --reset-author`) or just make sure future commits use the right identity.

**Google client libraries error with "Could not automatically determine credentials":** ADC is missing. Run `gcloud auth application-default login` and retry.

**`cloud-sql-proxy` exits with "permission denied" or "instance not authorized":** either the instance connection name is wrong, or your Google user does not have the `Cloud SQL Client` IAM role on that instance. Verify the name with admin and confirm your IAM bindings in the GCP console.

**Claude says the Atlassian OAuth session expired:** send the auth prompt again — *"Authenticate the Jira MCP and verify it works — list my accessible Jira projects."*

**`cloudflared tunnel run` fails with "couldn't read credentials":** your secret didn't contain `CLOUDFLARED_TOKEN` when the container was created. Ask admin to verify the `<dev_name>-api-secrets` Secret in your namespace, then re-run the bootstrap manually:

```bash
bash .devcontainer/on-create.sh
```

**Tunnel connects but the browser returns 502 / "Connection refused":** your app isn't listening on the port referenced in `config.yml`, or it's not bound to `localhost`. Verify inside the container:

```bash
curl -v http://localhost:<port>
```

**Tunnel connects but the browser shows `DNS_PROBE_FINISHED_NXDOMAIN`:** the DNS records for your subdomain are missing at the Cloudflare side. This is an admin task — ping whoever provisioned your environment.

**Cloudflare Access blocks you after login:** your email is not in the `@vendormint.com` domain, or you are not in the `Vendormint Team` Access group. Ask admin to add you.

**SSL warning on the app URL:** the Advanced Certificate doesn't cover your wildcard yet. Admin needs to re-order it with `*.<dev_name>.dev.vendormint.ai` included.

---

## Reference

| File | Purpose |
|---|---|
| `.devcontainer/devcontainer.json` | Installed features, VS Code extensions, lifecycle hooks. |
| `.devcontainer/on-create.sh` | Bootstrap: installs Claude Code, pulls k8s secrets, configures MCP servers and cloudflared. |
| `.devcontainer/cloudflared/config.yml.template` | Source template for `~/.cloudflared/config.yml`. |
| `../k8s-cloud-manager/` | Admin-side repo that creates the namespace, secrets, PVC and kubeconfig for each dev. |
