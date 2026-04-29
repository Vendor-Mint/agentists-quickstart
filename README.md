# K8s Cloud Workspace

Cloud-native DevContainer that runs inside a Kubernetes pod. Each developer gets an isolated namespace provisioned by `k8s-cloud-manager`, brings the workspace up with **DevPod**, and lands in a fully wired dev environment: Claude Code CLI, MCP servers (Playwright, GitHub, Context7, Filesystem, Atlassian), `gcloud`, `kubectl`, `helm`, Docker-in-Docker, Node.js, Python, .NET, Playwright with Chromium, and `cloudflared` for exposing local apps to the public internet via `*.<dev_name>.dev.vendormint.ai`.

---

## How you get here

DevPod reads `.devcontainer/` from this repository, so you do need it on your laptop. The flow is:

1. **Admin** provisions your environment with `k8s-cloud-manager` and sends you:
   - `kubeconfig-<dev_name>.yaml` — scoped to your namespace `dev-<dev_name>`.
   - GCP project ID, Cloud SQL region, Cloud SQL instance name, and the Cloud SQL **instance connection name** (`<project>:<region>:<instance>`).
2. You clone this repo, install **DevPod**, point its Kubernetes provider at the kubeconfig, and run `devpod up`.
3. DevPod builds the container in your namespace and runs `.devcontainer/on-create.sh` automatically. The post-create checklist below is what you have to do once the container is up — DevPod cannot automate steps that require interactive logins.

Throughout this document, `<dev_name>` is the name admin used when provisioning your environment (e.g. the one passed to `./provision-dev.sh <dev_name>`). It shows up in your namespace, your tunnel hostnames, and the kubeconfig filename.

---

## Local setup (one-time, on your laptop)

### 1. Clone this repository

```bash
git clone <repo-url> k8s-cloud-workspace
cd k8s-cloud-workspace
git checkout k8s-cloud-workspace
```

### 2. Install DevPod and `kubectl`

DevPod uses `kubectl` under the hood and you will also use it directly for sanity checks and debugging.

```bash
# macOS (Homebrew)
brew install --cask devpod
brew install kubectl

# Linux / other — see https://devpod.sh/ and https://kubernetes.io/docs/tasks/tools/
```

Verify both are on your PATH:

```bash
devpod version
kubectl version --client
```

### 3. Save the kubeconfig admin sent you

Keep it isolated from any other kubeconfig you may have:

```bash
mkdir -p ~/.kube
mv ~/Downloads/kubeconfig-<dev_name>.yaml ~/.kube/kubeconfig-<dev_name>.yaml
```

For direct `kubectl` usage (sanity checks, debugging) export `KUBECONFIG` so every new shell sees it. The DevPod provider in step 4 will get its own pointer to the same file, so DevPod is not affected by whether this env var is set or not.

```bash
# Persist in your shell rc (zsh shown — use ~/.bashrc for bash)
readlink -f ~/.kube/kubeconfig-<dev_name>.yaml
export KUBECONFIG=FILE_PATH
```

Sanity check — you should see your pod (or nothing yet) but never get `forbidden` for namespace `dev-<dev_name>`:

```bash
kubectl get pods -n dev-<dev_name>
```

### 4. Configure DevPod's Kubernetes provider

Pass the kubeconfig path explicitly with `-o KUBERNETES_CONFIG=...` so DevPod's resolution does not depend on an env var being set in the shell where you run it. The other values mirror the cluster-side `ResourceQuota` defined in `k8s-cloud-manager/.env.example` — going over them makes the pod fail to schedule.

```bash
devpod provider add kubernetes
```
```bash
devpod provider use kubernetes \
  -o KUBERNETES_CONFIG=$HOME/.kube/kubeconfig-<dev_name>.yaml \
  -o KUBERNETES_NAMESPACE=dev-<dev_name> \
  -o CREATE_NAMESPACE=false \
  -o WORKSPACE_VOLUME_MOUNT=/workspaces \
  -o ARCHITECTURE=amd64 \
  -o STORAGE_CLASS=ssd-large \
  -o DISK_SIZE=50Gi \
  -o RESOURCES=requests.cpu=8,requests.memory=15Gi,limits.cpu=16,limits.memory=30Gi
```

| Option | Value | Why |
|---|---|---|
| `KUBERNETES_CONFIG` | `$HOME/.kube/kubeconfig-<dev_name>.yaml` | Path to the kubeconfig admin sent you. |
| `KUBERNETES_NAMESPACE` | `dev-<dev_name>` | Your scoped kubeconfig only allows this namespace. |
| `CREATE_NAMESPACE` | `false` | The namespace was already created by `k8s-cloud-manager`. Your kubeconfig has no rights to create namespaces, so leaving the default (`true`) makes `devpod up` fail with a `forbidden` error. |
| `WORKSPACE_VOLUME_MOUNT` | `/workspaces` | Mounts the **parent** `/workspaces` directory instead of just the single-repo path (`/workspaces/<workspace-id>`). Lets you clone or create additional repos alongside this one and have them all persist on the same PVC. |
| `ARCHITECTURE` | `amd64` | Forces the pod to schedule on `amd64` nodes only. The base image and several binaries pulled by `on-create.sh` (e.g. `cloud-sql-proxy.linux.amd64`) are amd64-only — landing on an arm64 node would crash with `exec format error`. |
| `STORAGE_CLASS` | `ssd-large` | Rackspace's default storage class caps PVCs at 20Gi, which is too small once dockerless writes the devcontainer rootfs into `/workspaces/.dockerless/`. The `ssd-large` class allows the larger `DISK_SIZE` below. |
| `DISK_SIZE` | `50Gi` | Enough headroom for the dockerless build (`/workspaces/.dockerless/` ≈ 1-2Gi) plus the developer's clones and caches. Requires `STORAGE_CLASS=ssd-large`. |
| `RESOURCES` | `requests.cpu=6,requests.memory=12Gi,limits.cpu=8,limits.memory=15Gi` | Matches `REQ_CPU` / `REQ_MEM` / `LIMIT_CPU` / `LIMIT_MEM` from the manager's defaults. |

### 5. Bring up the workspace

```bash
devpod up .
```

DevPod streams the image build, the pod start, and the bootstrap output of `.devcontainer/on-create.sh` (5 numbered steps). When `[5/5] Configuring Cloudflared tunnel` finishes, the workspace is ready and your IDE / shell attaches.

---

## Post-create checklist

Run these inside the workspace, once.

### 1. Authenticate GitHub CLI (SSH)

Both day-to-day `git` work and the **GitHub MCP server** depend on `gh` being logged in. Inside the container:

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

Copy the one-time code, open the URL on your local machine, paste, approve. `gh` uploads the public key to your GitHub account and saves the private key at `~/.ssh/id_ed25519`. Verify:

```bash
gh auth status
ssh -T git@github.com
```

### 2. Configure your Git identity

`gh auth login` does **not** set the commit author. Use the same email as your GitHub account so commits are attributed properly:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@vendormint.com"
```

### 3. Configure `gcloud` and the Cloud SQL Auth Proxy

The container ships with `gcloud` and `cloud-sql-proxy` pre-installed.

#### 3.1 Log in and select the project

```bash
gcloud auth login
gcloud config set project <gcp-project-id>      # value sent by admin
```

#### 3.2 Set up Application Default Credentials (ADC)

Used by Google client libraries and `cloud-sql-proxy`:

```bash
gcloud auth application-default login
```

#### 3.3 Connect to Cloud SQL via `cloud-sql-proxy`

> Run this inside `tmux` so it stays alive across terminal closures (see [Daily workflow](#daily-workflow) below).

```bash
cloud-sql-proxy <project>:<region>:<instance> --port 5432
```

Replace `<project>:<region>:<instance>` with the **instance connection name** sent by admin. Your local apps can now reach the database at `localhost:5432`.

### 4. Configure and run your Cloudflare tunnel

`on-create.sh` already pulled your tunnel token from the namespace secret and wrote:

- `~/.cloudflared/<tunnel-id>.json` — credentials (do not edit).
- `~/.cloudflared/config.yml` — routing config rendered from `.devcontainer/cloudflared/config.yml.template`. **This is the file you edit.**

#### Add ingress rules for your apps

Open `~/.cloudflared/config.yml` and uncomment / add one entry per app you want to expose. Hostnames must be `<app>.<dev_name>.dev.vendormint.ai` (wildcard DNS covers everything). The trailing `http_status:404` catch-all must stay last.

Example exposing a frontend on 4321, an API on 3000, and a websocket on 8080:

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

Validate the YAML before running it:

```bash
cloudflared tunnel ingress validate
```

#### Run the tunnel

> Run this inside `tmux` for the same reason as `cloud-sql-proxy` — see [Daily workflow](#daily-workflow).

```bash
cloudflared tunnel run
```

You will see four `Registered tunnel connection` lines once it is up. After editing `config.yml`, restart the tunnel to pick up the new rules.

Your apps are now reachable at `https://<app>.<dev_name>.dev.vendormint.ai`, gated by Cloudflare Access — log in with your `@vendormint.com` email.

### 5. Verify all Claude Code MCP servers

`on-create.sh` registered five MCP servers in Claude Code. Open a Claude Code terminal:

```bash
claude
```

Inside Claude, type:

```
/mcp
```

You should see five entries:

| MCP | Expected status |
|---|---|
| `playwright` | ✓ connected |
| `github` | ✓ connected (uses `gh` from step 1) |
| `context7` | ✓ connected |
| `server-filesystem` | ✓ connected |
| `atlassian` | ⚠ needs auth on first use |

For the Atlassian one, the OAuth flow is driven by Claude itself. Send a prompt like:

```text
Authenticate the Jira MCP and verify it works — show my Jira profile information.
```

Claude will:

1. Attempt a Jira tool call.
2. Print an OAuth URL in the terminal.
3. You open the URL on your **local** machine, approve the app, and return.
4. Claude retries the tool call and shows your profile, confirming it is wired up.

After that, run `/mcp` again — all five should show as connected. Sessions persist on disk; if Claude later says the session expired, just re-run the same prompt.

---

## Daily workflow

Three terminals. Keep the long-running ones in `tmux` so they survive disconnects, terminal closures, and SSH drops.

### Terminal 1 — `tmux` with long-running services

Start the session and split it into two panes:

```bash
tmux new -s services        # creates session "services"
# Then inside tmux:
#   Ctrl-b "    → split horizontally
#   Ctrl-b o    → switch panes
```

In one pane:

```bash
cloud-sql-proxy <project>:<region>:<instance> --port 5432
```

In the other:

```bash
cloudflared tunnel run
```

Detach with `Ctrl-b d`. Reattach later with `tmux attach -t services`. These two will keep running as long as the pod is alive.

### Terminal 2 — Claude Code

Any regular terminal (no `tmux` needed):

```bash
claude
```

### Terminal 3 — Free for ad-hoc commands

Any regular terminal. Run your app, `git`, `kubectl`, `npm install`, scratch builds, anything that is not long-lived.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `gh` says not authenticated | Re-run `gh auth login` and pick `SSH` again. |
| `git push` → `Permission denied (publickey)` | The SSH key did not upload. `gh auth status` to confirm; if missing, `gh auth login` and answer **Yes** to *Generate a new SSH key*. |
| Commits show up as `vscode <vscode@...>` on GitHub | You skipped step 2 (Git identity). Set `user.name` / `user.email` and amend with `git commit --amend --reset-author`. |
| Google libraries error: *"Could not automatically determine credentials"* | Run `gcloud auth application-default login`. |
| `cloud-sql-proxy` exits with *"permission denied"* | Wrong instance connection name, or your Google user lacks the `Cloud SQL Client` IAM role. Confirm both with admin. |
| Claude says Atlassian session expired | Re-send the auth prompt: *"Authenticate the Jira MCP and verify it works."* |
| Playwright MCP says *"Chrome for Testing not available"* / *"Executable doesn't exist"* | The MCP-bundled browser was not installed (or version mismatch). Run inside the container: `npx @playwright/mcp install-browser chrome-for-testing` |
| `cloudflared tunnel run` → *"couldn't read credentials"* | Your secret did not contain `CLOUDFLARED_TOKEN` when the container was created. Re-run `bash .devcontainer/on-create.sh`. |
| Browser → 502 / Connection refused after Cloudflare login | App not listening on the port in `config.yml`. Check with `curl http://localhost:<port>` inside the container. |
| Browser → SSL handshake failure on `https://<app>.<dev_name>...` | The Advanced Certificate does not yet cover `*.<dev_name>.dev.vendormint.ai`. Admin task — ping admin. |
| Browser → `DNS_PROBE_FINISHED_NXDOMAIN` | DNS records missing for your subdomain. Admin task — ping admin. |
| Cloudflare Access blocks you after login | Your email is not `@vendormint.com`, or you are not in the `Vendormint Team` Access group. Ping admin. |

---

## Reference

| File | Purpose |
|---|---|
| `.devcontainer/devcontainer.json` | Installed features, lifecycle hooks. |
| `.devcontainer/on-create.sh` | Bootstrap: installs Claude Code, pulls k8s secrets, configures MCPs and cloudflared. |
| `.devcontainer/cloudflared/config.yml.template` | Source template for `~/.cloudflared/config.yml`. |
| `../k8s-cloud-manager/` | Admin-side repo that creates the namespace, secrets, PVC and kubeconfig for each dev. |
